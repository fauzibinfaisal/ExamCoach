import 'package:exam_coach/services/sync/domain/sync_outbox_item.dart';

enum SyncRemoteOutcome {
  accepted,
  duplicate,
  superseded,
  retryableFailure,
  rejected,
}

class SyncRemoteResult {
  const SyncRemoteResult({
    required this.operationId,
    required this.outcome,
    this.remoteRevision,
    this.message,
  });

  final String operationId;
  final SyncRemoteOutcome outcome;
  final int? remoteRevision;
  final String? message;
}

class SyncBatchResponse {
  SyncBatchResponse(Iterable<SyncRemoteResult> results)
    : results = List.unmodifiable(results);

  final List<SyncRemoteResult> results;

  SyncRemoteResult? resultFor(String operationId) {
    for (final result in results) {
      if (result.operationId == operationId) {
        return result;
      }
    }
    return null;
  }
}

abstract interface class SyncRemoteGateway {
  Future<SyncBatchResponse> pushBatch(List<SyncOutboxItem> operations);
}

class SyncTransportException implements Exception {
  const SyncTransportException(this.message);

  final String message;

  @override
  String toString() => 'SyncTransportException: $message';
}
