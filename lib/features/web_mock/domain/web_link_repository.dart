class WebLinkFailure implements Exception {
  const WebLinkFailure(this.code);
  final String code;
  String get message => switch (code) {
    'unauthenticated' => 'Masuk ke akun untuk mengelola link.',
    'already-exists' =>
      'Masih ada link aktif. Muat ulang lalu cabut sebelum membuat pengganti.',
    'resource-exhausted' => 'Batas permintaan tercapai. Coba lagi nanti.',
    'unavailable' => 'Pembuatan link belum tersedia pada lingkungan ini.',
    'failed-precondition' =>
      'Tryout berubah atau belum tersedia. Muat ulang daftar.',
    _ =>
      'Permintaan belum dapat dipastikan. Muat ulang untuk memeriksa link sebelum mencoba lagi.',
  };
  @override
  String toString() => 'WebLinkFailure';
}

enum WebLinkStatus { active, claimed, expired, revoked, completed, timeout }

class WebTryout {
  const WebTryout({
    required this.id,
    required this.title,
    required this.fingerprint,
    required this.questionCount,
    required this.durationSeconds,
  });
  final String id;
  final String title;
  final String fingerprint;
  final int questionCount;
  final int durationSeconds;
}

class WebLinkSummary {
  const WebLinkSummary({
    required this.id,
    required this.tryoutId,
    required this.fingerprint,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
  });
  final String id;
  final String tryoutId;
  final String fingerprint;
  final WebLinkStatus status;
  final DateTime createdAt;
  final DateTime expiresAt;
  bool get canRevoke =>
      status == WebLinkStatus.active || status == WebLinkStatus.claimed;
}

class WebLinkManagement {
  WebLinkManagement({
    required this.serverNow,
    required List<WebTryout> tryouts,
    required List<WebLinkSummary> links,
  }) : tryouts = List.unmodifiable(tryouts),
       links = List.unmodifiable(links);
  final DateTime serverNow;
  final List<WebTryout> tryouts;
  final List<WebLinkSummary> links;
}

// Intentionally no JSON, equality/debug properties or persistence adapter.
class WebLinkCreated {
  const WebLinkCreated({
    required this.link,
    required this.serverNow,
    required this.launchUrl,
  });
  final WebLinkSummary link;
  final DateTime serverNow;
  final String? launchUrl;
  @override
  String toString() => 'WebLinkCreated(redacted)';
}

abstract interface class WebLinkRepository {
  bool get isAvailable;
  String? get currentUserId;
  Future<WebLinkManagement> load();
  Future<WebLinkCreated> create(WebTryout tryout, String requestId);
  Future<WebLinkSummary> revoke(String linkId);
}

class UnavailableWebLinkRepository implements WebLinkRepository {
  const UnavailableWebLinkRepository();
  @override
  bool get isAvailable => false;
  @override
  String? get currentUserId => null;
  @override
  Future<WebLinkManagement> load() async =>
      throw const WebLinkFailure('unavailable');
  @override
  Future<WebLinkCreated> create(WebTryout tryout, String requestId) async =>
      throw const WebLinkFailure('unavailable');
  @override
  Future<WebLinkSummary> revoke(String linkId) async =>
      throw const WebLinkFailure('unavailable');
}
