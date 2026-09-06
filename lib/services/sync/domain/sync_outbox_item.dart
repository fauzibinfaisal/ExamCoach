enum SyncOutboxStatus { pending, synced }

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
}
