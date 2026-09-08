import 'package:exam_coach/services/sync/domain/remote_learning_snapshot.dart';

class AccountBindingConflict implements Exception {
  const AccountBindingConflict({
    required this.boundUserId,
    required this.requestedUserId,
  });

  final String boundUserId;
  final String requestedUserId;

  @override
  String toString() =>
      'Data perangkat terikat ke akun lain. Hapus data lokal secara eksplisit '
      'sebelum mengganti akun.';
}

class AccountClaimResult {
  const AccountClaimResult({
    required this.userId,
    required this.newBinding,
    required this.migratedSessions,
    required this.migratedAnalyticsEvents,
    required this.rewrittenOutboxOperations,
  });

  final String userId;
  final bool newBinding;
  final int migratedSessions;
  final int migratedAnalyticsEvents;
  final int rewrittenOutboxOperations;

  bool get claimedLocalData =>
      migratedSessions > 0 ||
      migratedAnalyticsEvents > 0 ||
      rewrittenOutboxOperations > 0;
}

enum RecoveryImportStatus { imported, emptyRemote, skippedLocalData }

class RecoveryImportResult {
  const RecoveryImportResult({
    required this.status,
    this.sessionCount = 0,
    this.answerCount = 0,
  });

  final RecoveryImportStatus status;
  final int sessionCount;
  final int answerCount;
}

abstract interface class AccountDataStore {
  Future<String?> loadBoundUserId();

  Future<AccountClaimResult> claimForUser(
    String userId, {
    required DateTime claimedAt,
  });

  Future<RecoveryImportResult> importRecoverySnapshot(
    RemoteLearningSnapshot snapshot, {
    required DateTime recoveredAt,
  });
}
