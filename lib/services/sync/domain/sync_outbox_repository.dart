import 'package:exam_coach/services/sync/domain/sync_outbox_item.dart';

abstract interface class SyncOutboxRepository {
  Future<List<SyncOutboxItem>> getPending({int limit = 50});

  Future<void> markAttemptFailed(String operationId, String error);

  Future<void> markSynced(String operationId);
}
