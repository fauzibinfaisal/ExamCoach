import 'package:cloud_functions/cloud_functions.dart';
import 'package:exam_coach/features/web_mock/domain/web_link_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseWebLinkRepository implements WebLinkRepository {
  const FirebaseWebLinkRepository({
    required this._functions,
    required this._auth,
  });
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  @override
  bool get isAvailable => true;
  @override
  String? get currentUserId => _auth.currentUser?.uid;

  Future<Map<String, Object?>> _call(
    String name,
    Map<String, Object?> data,
  ) async {
    final uid = currentUserId;
    if (uid == null) throw const WebLinkFailure('unauthenticated');
    try {
      final response = await _functions
          .httpsCallable(
            name,
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          )
          .call(<String, Object?>{'protocolVersion': 1, ...data});
      if (currentUserId != uid) throw const WebLinkFailure('unauthenticated');
      final root = _object(response.data);
      if (root['protocolVersion'] != 1) {
        throw const WebLinkFailure('invalid-response');
      }
      return root;
    } on FirebaseFunctionsException catch (error) {
      // Never forward SDK message/details or payloads to UI, logs or Crashlytics.
      const codes = {
        'unauthenticated',
        'already-exists',
        'resource-exhausted',
        'unavailable',
        'failed-precondition',
      };
      throw WebLinkFailure(codes.contains(error.code) ? error.code : 'unknown');
    } on WebLinkFailure {
      rethrow;
    } on Object {
      throw const WebLinkFailure('unknown');
    }
  }

  @override
  Future<WebLinkManagement> load() async =>
      decodeManagement(await _call('getWebMockLinkManagement', {}));

  @override
  Future<WebLinkCreated> create(WebTryout tryout, String requestId) async {
    final result = decodeCreated(
      await _call('createWebMockLink', {
        'requestId': requestId,
        'tryoutId': tryout.id,
        'contentFingerprint': tryout.fingerprint,
      }),
    );
    if (result.link.tryoutId != tryout.id ||
        result.link.fingerprint != tryout.fingerprint) {
      throw const WebLinkFailure('invalid-response');
    }
    return result;
  }

  @override
  Future<WebLinkSummary> revoke(String linkId) async {
    final root = await _call('revokeWebMockLink', {'linkId': linkId});
    _keys(root, {'protocolVersion', 'serverNowMs', 'link'});
    _date(root['serverNowMs']);
    final link = _link(root['link']);
    if (link.id != linkId || link.canRevoke) {
      throw const WebLinkFailure('invalid-response');
    }
    return link;
  }

  static WebLinkManagement decodeManagement(Object? data) {
    final root = _object(data);
    _keys(root, {'protocolVersion', 'serverNowMs', 'tryouts', 'links'});
    if (root['protocolVersion'] != 1) {
      throw const WebLinkFailure('invalid-response');
    }
    final tryouts = _list(root['tryouts']).map((value) {
      final item = _object(value);
      _keys(item, {
        'tryoutId',
        'title',
        'contentFingerprint',
        'questionCount',
        'durationSeconds',
      });
      return WebTryout(
        id: _id(item['tryoutId']),
        title: _string(item['title'], 120),
        fingerprint: _fingerprint(item['contentFingerprint']),
        questionCount: _integer(item['questionCount'], 1, 500),
        durationSeconds: _integer(item['durationSeconds'], 60, 14400),
      );
    }).toList();
    final links = _list(root['links']).map(_link).toList();
    if (tryouts.map((t) => t.id).toSet().length != tryouts.length ||
        links.map((l) => l.tryoutId).toSet().length != links.length) {
      throw const WebLinkFailure('invalid-response');
    }
    return WebLinkManagement(
      serverNow: _date(root['serverNowMs']),
      tryouts: tryouts,
      links: links,
    );
  }

  static WebLinkCreated decodeCreated(Object? data) {
    final root = _object(data);
    _keys(root, {'protocolVersion', 'serverNowMs', 'link', 'launchUrl'});
    if (root['protocolVersion'] != 1) {
      throw const WebLinkFailure('invalid-response');
    }
    final url = root['launchUrl'];
    if (url != null &&
        (url is! String ||
            !RegExp(
              r'^http://127\.0\.0\.1:5173/mock-test#[A-Za-z0-9_-]{43}$',
            ).hasMatch(url))) {
      throw const WebLinkFailure('invalid-response');
    }
    final link = _link(root['link']);
    if (url != null && link.status != WebLinkStatus.active) {
      throw const WebLinkFailure('invalid-response');
    }
    return WebLinkCreated(
      link: link,
      serverNow: _date(root['serverNowMs']),
      launchUrl: url as String?,
    );
  }

  static Map<String, Object?> _object(Object? value) {
    if (value is Map && value.keys.every((k) => k is String)) {
      return Map<String, Object?>.from(value);
    }
    throw const WebLinkFailure('invalid-response');
  }

  static void _keys(Map<String, Object?> value, Set<String> keys) {
    if (value.length != keys.length || !keys.containsAll(value.keys)) {
      throw const WebLinkFailure('invalid-response');
    }
  }

  static List<Object?> _list(Object? value) {
    if (value is List && value.length <= 20) return value;
    throw const WebLinkFailure('invalid-response');
  }

  static String _string(Object? value, int max) {
    if (value is String && value.isNotEmpty && value.length <= max) {
      return value;
    }
    throw const WebLinkFailure('invalid-response');
  }

  static String _id(Object? value) {
    final text = _string(value, 80);
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(text)) {
      throw const WebLinkFailure('invalid-response');
    }
    return text;
  }

  static String _fingerprint(Object? value) {
    final text = _string(value, 64);
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(text)) {
      throw const WebLinkFailure('invalid-response');
    }
    return text;
  }

  static int _integer(Object? value, int min, int max) {
    if (value is num &&
        value.isFinite &&
        value == value.toInt() &&
        value >= min &&
        value <= max) {
      return value.toInt();
    }
    throw const WebLinkFailure('invalid-response');
  }

  static DateTime _date(Object? value) => DateTime.fromMillisecondsSinceEpoch(
    _integer(value, 1, 8640000000000000),
    isUtc: true,
  );
  static WebLinkSummary _link(Object? value) {
    final item = _object(value);
    _keys(item, {
      'linkId',
      'tryoutId',
      'contentFingerprint',
      'status',
      'createdAtMs',
      'expiresAtMs',
    });
    final status = WebLinkStatus.values
        .where((s) => s.name == item['status'])
        .firstOrNull;
    final createdAt = _date(item['createdAtMs']);
    final expiresAt = _date(item['expiresAtMs']);
    if (status == null ||
        expiresAt.difference(createdAt) != const Duration(hours: 12)) {
      throw const WebLinkFailure('invalid-response');
    }
    return WebLinkSummary(
      id: _id(item['linkId']),
      tryoutId: _id(item['tryoutId']),
      fingerprint: _fingerprint(item['contentFingerprint']),
      status: status,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }
}
