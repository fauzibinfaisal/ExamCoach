import 'dart:async';

import 'package:exam_coach/features/auth/application/auth_cubit.dart';
import 'package:exam_coach/features/auth/application/auth_state.dart';
import 'package:exam_coach/features/auth/domain/auth_user.dart';
import 'package:exam_coach/features/web_mock/presentation/web_link_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:exam_coach/features/web_mock/application/web_link_cubit.dart';
import 'package:exam_coach/features/web_mock/data/firebase_web_link_repository.dart';
import 'package:exam_coach/features/web_mock/domain/web_link_repository.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 9, 22);
final _tryout = WebTryout(
  id: 'fixture',
  title: 'Local test',
  fingerprint: 'a' * 64,
  questionCount: 6,
  durationSeconds: 360,
);
final _link = WebLinkSummary(
  id: 'b' * 32,
  tryoutId: _tryout.id,
  fingerprint: _tryout.fingerprint,
  status: WebLinkStatus.active,
  createdAt: _now,
  expiresAt: _now.add(const Duration(hours: 12)),
);
final _url = 'http://127.0.0.1:5173/mock-test#${'T' * 43}';
WebLinkCreated _created() =>
    WebLinkCreated(link: _link, serverNow: _now, launchUrl: _url);

class _Repository implements WebLinkRepository {
  @override
  bool isAvailable = true;
  @override
  String? currentUserId = 'alice';
  Completer<WebLinkCreated>? pending;
  Object? failure;
  final requestIds = <String>[];
  @override
  Future<WebLinkManagement> load() async =>
      WebLinkManagement(serverNow: _now, tryouts: [_tryout], links: []);
  @override
  Future<WebLinkCreated> create(WebTryout tryout, String requestId) async {
    requestIds.add(requestId);
    if (failure != null) throw failure!;
    return pending == null ? _created() : pending!.future;
  }

  @override
  Future<WebLinkSummary> revoke(String id) async => WebLinkSummary(
    id: id,
    tryoutId: _link.tryoutId,
    fingerprint: _link.fingerprint,
    status: WebLinkStatus.revoked,
    createdAt: _now,
    expiresAt: _link.expiresAt,
  );
}

Map<String, Object?> _jsonLink() => {
  'linkId': _link.id,
  'tryoutId': _tryout.id,
  'contentFingerprint': _tryout.fingerprint,
  'status': 'active',
  'createdAtMs': _now.millisecondsSinceEpoch,
  'expiresAtMs': _link.expiresAt.millisecondsSinceEpoch,
};
Map<String, Object?> _response() => {
  'protocolVersion': 1,
  'serverNowMs': _now.millisecondsSinceEpoch,
  'link': _jsonLink(),
  'launchUrl': _url,
};

class _Auth extends Cubit<AuthState> implements AuthCubit {
  _Auth()
    : super(
        const AuthState(
          status: AuthStatus.signedIn,
          user: AuthUser(
            uid: 'alice',
            email: 'alice@example.com',
            emailVerified: true,
          ),
        ),
      );
  void leave() => emit(const AuthState.signedOut());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('mobile management creates, redacts and revokes at large text', (
    tester,
  ) async {
    final auth = _Auth();
    final repository = _Repository();
    await tester.pumpWidget(
      RepositoryProvider<WebLinkRepository>.value(
        value: repository,
        child: BlocProvider<AuthCubit>.value(
          value: auth,
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: const WebLinkPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Buat link'), 250);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buat link'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('copy-web-link')),
      -250,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('copy-web-link')), findsOneWidget);
    expect(find.textContaining('http://'), findsNothing);
    await tester.scrollUntilVisible(find.text('Cabut link'), 250);
    await tester.pumpAndSettle();
    expect(find.textContaining('Status: Aktif'), findsOneWidget);
    await tester.tap(find.text('Cabut link'));
    await tester.pumpAndSettle();
    expect(find.text('Status: Dicabut'), findsOneWidget);
    expect(find.byKey(const Key('copy-web-link')), findsNothing);
    expect(tester.takeException(), isNull);
    repository.currentUserId = null;
    auth.leave();
    await tester.pumpAndSettle();
    expect(find.text('Masuk untuk membuat link'), findsOneWidget);
    expect(find.text('Status: Dicabut'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await auth.close();
  });

  test(
    'capability never enters emitted states and explicit copy consumes it',
    () async {
      final repository = _Repository();
      final cubit = WebLinkCubit(repository);
      final states = <WebLinkState>[];
      final subscription = cubit.stream.listen(states.add);
      await cubit.load();
      await cubit.create(_tryout);
      expect(cubit.state.hasCopy, isTrue);
      expect(cubit.state.management!.links.single.id, _link.id);
      expect(
        repository.requestIds.single,
        matches(RegExp(r'^[A-Za-z0-9_-]{32}$')),
      );
      String? copied;
      expect(await cubit.copy((url) async => copied = url), isTrue);
      expect(copied, _url);
      expect(cubit.state.hasCopy, isFalse);
      expect(await cubit.copy((_) async => fail('second copy')), isFalse);
      expect(
        states.every(
          (s) =>
              !s.toString().contains(_url) &&
              !(s.message?.contains(_url) ?? false),
        ),
        isTrue,
      );
      expect(_created().toString(), isNot(contains(_url)));
      await subscription.cancel();
      await cubit.close();
    },
  );

  test(
    'sign-out and lifecycle clear discard pending create responses',
    () async {
      for (final accountChange in [true, false]) {
        final repository = _Repository()..pending = Completer<WebLinkCreated>();
        final cubit = WebLinkCubit(repository);
        final pending = cubit.create(_tryout);
        if (accountChange) {
          repository.currentUserId = 'bob';
        } else {
          cubit.clear();
        }
        repository.pending!.complete(_created());
        await pending;
        expect(cubit.state.hasCopy, isFalse);
        expect(cubit.state.management, isNull);
        expect(
          await cubit.copy((_) async => fail('stale capability copied')),
          isFalse,
        );
        await cubit.close();
      }
    },
  );

  test(
    'double tap issues one request and close discards late response',
    () async {
      final repository = _Repository()..pending = Completer<WebLinkCreated>();
      final cubit = WebLinkCubit(repository);
      final pending = cubit.create(_tryout);
      await cubit.create(_tryout);
      expect(repository.requestIds, hasLength(1));
      await cubit.close();
      repository.pending!.complete(_created());
      await pending;
      expect(cubit.state.hasCopy, isFalse);
    },
  );

  test('refresh, revoke and account change remove copy access', () async {
    final repository = _Repository();
    final cubit = WebLinkCubit(repository);
    await cubit.load();
    await cubit.create(_tryout);
    await cubit.revoke(_link);
    expect(cubit.state.hasCopy, isFalse);
    expect(cubit.state.management!.links.single.status, WebLinkStatus.revoked);
    await cubit.create(_tryout);
    await cubit.load();
    expect(cubit.state.hasCopy, isFalse);
    await cubit.create(_tryout);
    repository.currentUserId = null;
    expect(await cubit.copy((_) async => fail('signed-out copy')), isFalse);
    await cubit.close();
  });

  test('SDK and clipboard failures never expose secret text', () async {
    final repository = _Repository()..failure = StateError(_url);
    final cubit = WebLinkCubit(repository);
    await cubit.create(_tryout);
    expect(cubit.state.message, isNot(contains(_url)));
    repository.failure = null;
    await cubit.create(_tryout);
    expect(await cubit.copy((_) async => throw StateError(_url)), isFalse);
    expect(cubit.state.message, isNot(contains(_url)));
    expect(cubit.state.hasCopy, isFalse);
    await cubit.close();
  });

  test(
    'strict response rejects unknown fields, non-loopback URLs and client TTL',
    () {
      expect(
        FirebaseWebLinkRepository.decodeCreated(_response()).launchUrl,
        _url,
      );
      for (final response in [
        {..._response(), 'launchUrl': 'https://evil.example/#secret'},
        {..._response(), 'launchUrl': '$_url?uid=alice'},
        {..._response(), 'rawToken': 'secret'},
        {
          ..._response(),
          'link': {
            ..._jsonLink(),
            'expiresAtMs': _now.millisecondsSinceEpoch + 1,
          },
        },
        {
          ..._response(),
          'link': {..._jsonLink(), 'ownerUid': 'alice'},
        },
        {
          ..._response(),
          'link': {..._jsonLink(), 'status': 'completed'},
        },
        {..._response(), 'protocolVersion': 2},
      ]) {
        expect(
          () => FirebaseWebLinkRepository.decodeCreated(response),
          throwsA(isA<WebLinkFailure>()),
        );
      }
      expect(
        FirebaseWebLinkRepository.decodeCreated({
          ..._response(),
          'launchUrl': null,
        }).launchUrl,
        isNull,
      );
    },
  );

  test(
    'management validates bounded catalog, safe projection and unique slots',
    () {
      final response = {
        'protocolVersion': 1,
        'serverNowMs': _now.millisecondsSinceEpoch,
        'tryouts': <Object?>[],
        'links': [_jsonLink()],
      };
      expect(
        FirebaseWebLinkRepository.decodeManagement(response).links.single.id,
        _link.id,
      );
      for (final invalid in [
        {
          ...response,
          'links': [_jsonLink(), _jsonLink()],
        },
        {...response, 'links': List.filled(21, _jsonLink())},
        {
          ...response,
          'links': [
            {..._jsonLink(), 'tokenHash': 'secret'},
          ],
        },
        {
          ...response,
          'tryouts': [
            {
              'tryoutId': 'bad',
              'title': 'x' * 121,
              'contentFingerprint': 'a' * 64,
              'questionCount': 0,
              'durationSeconds': 60,
            },
          ],
        },
      ]) {
        expect(
          () => FirebaseWebLinkRepository.decodeManagement(invalid),
          throwsA(isA<WebLinkFailure>()),
        );
      }
    },
  );
}
