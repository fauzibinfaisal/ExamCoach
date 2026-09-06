import 'package:exam_coach/services/sync/domain/sync_outbox_item.dart';

abstract interface class SyncOutboxRepository {
  Future<List<SyncOutboxItem>> getPending({int limit = 50});

  Future<List<SyncOutboxItem>> getReady({
    required DateTime now,
    int limit = 50,
  });

  Future<void> markAttemptFailed(
    String operationId,
    String error, {
    required DateTime attemptedAt,
    DateTime? nextAttemptAt,
    required bool deadLetter,
  });

  Future<void> markSynced(
    String operationId, {
    required DateTime syncedAt,
    required SyncAcknowledgement acknowledgement,
    int? remoteRevision,
  });

  Future<int> pruneSynced({required DateTime before, int limit = 200});
}
