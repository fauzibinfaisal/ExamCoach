enum SyncOutboxStatus { pending, synced, deadLetter }

enum SyncAcknowledgement { accepted, duplicate, superseded }

class SyncOutboxItem {
  const SyncOutboxItem({
    required this.operationId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.createdAt,
    required this.attempts,
    required this.status,
    this.lastError,
    this.lastAttemptAt,
    this.nextAttemptAt,
    this.syncedAt,
    this.deadLetteredAt,
    this.acknowledgement,
    this.remoteRevision,
  });

  final String operationId;
  final String entityType;
  final String entityId;
  final String operation;
  final Map<String, Object?> payload;
  final DateTime createdAt;
  final int attempts;
  final SyncOutboxStatus status;
  final String? lastError;
  final DateTime? lastAttemptAt;
  final DateTime? nextAttemptAt;
  final DateTime? syncedAt;
  final DateTime? deadLetteredAt;
  final SyncAcknowledgement? acknowledgement;
  final int? remoteRevision;

  bool isReadyAt(DateTime now) =>
      status == SyncOutboxStatus.pending &&
      (nextAttemptAt == null || !nextAttemptAt!.isAfter(now));
}
