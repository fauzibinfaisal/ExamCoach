import 'package:exam_coach/services/sync/domain/connectivity_monitor.dart';
import 'package:exam_coach/services/sync/domain/sync_outbox_item.dart';
import 'package:exam_coach/services/sync/domain/sync_outbox_repository.dart';
import 'package:exam_coach/services/sync/domain/sync_remote_gateway.dart';
import 'package:exam_coach/services/sync/domain/sync_retry_policy.dart';
import 'package:exam_coach/services/sync/domain/sync_run_summary.dart';

typedef SyncUtcNow = DateTime Function();

abstract interface class SyncRunner {
  Future<SyncRunSummary> runUntilIdle();
}

class SyncWorker implements SyncRunner {
  factory SyncWorker({
    required SyncOutboxRepository outboxRepository,
    required SyncRemoteGateway remoteGateway,
    required ConnectivityMonitor connectivityMonitor,
    SyncRetryPolicy retryPolicy = const SyncRetryPolicy(),
    Duration syncedRetention = const Duration(days: 7),
    int batchSize = 25,
    int maxBatchesPerRun = 10,
    SyncUtcNow? now,
  }) {
    if (batchSize <= 0 || maxBatchesPerRun <= 0) {
      throw ArgumentError('Batch size and maximum batches must be positive.');
    }
    if (syncedRetention.isNegative) {
      throw ArgumentError.value(
        syncedRetention,
        'syncedRetention',
        'cannot be negative',
      );
    }
    return SyncWorker._(
      outboxRepository,
      remoteGateway,
      connectivityMonitor,
      retryPolicy,
      syncedRetention,
      batchSize,
      maxBatchesPerRun,
      now ?? (() => DateTime.now().toUtc()),
    );
  }

  SyncWorker._(
    this._outboxRepository,
    this._remoteGateway,
    this._connectivityMonitor,
    this._retryPolicy,
    this._syncedRetention,
    this._batchSize,
    this._maxBatchesPerRun,
    this._now,
  );

  final SyncOutboxRepository _outboxRepository;
  final SyncRemoteGateway _remoteGateway;
  final ConnectivityMonitor _connectivityMonitor;
  final SyncRetryPolicy _retryPolicy;
  final Duration _syncedRetention;
  final int _batchSize;
  final int _maxBatchesPerRun;
  final SyncUtcNow _now;

  Future<SyncRunSummary>? _inFlight;

  @override
  Future<SyncRunSummary> runUntilIdle() {
    final existing = _inFlight;
    if (existing != null) {
      return existing;
    }
    final run = _runGuarded();
    _inFlight = run;
    return run;
  }

  Future<SyncRunSummary> _runGuarded() async {
    try {
      return await _run();
    } finally {
      _inFlight = null;
    }
  }

  Future<SyncRunSummary> _run() async {
    if (!await _connectivityMonitor.isOnline) {
      return const SyncRunSummary(skippedOffline: true);
    }

    final accumulator = _SyncAccumulator();
    final startedAt = _utcNow();
    accumulator.pruned = await _outboxRepository.pruneSynced(
      before: startedAt.subtract(_syncedRetention),
    );

    for (var batchIndex = 0; batchIndex < _maxBatchesPerRun; batchIndex++) {
      final now = _utcNow();
      final operations = await _outboxRepository.getReady(
        now: now,
        limit: _batchSize,
      );
      if (operations.isEmpty) {
        break;
      }

      accumulator.batches++;
      accumulator.attempted += operations.length;
      try {
        final response = await _remoteGateway.pushBatch(operations);
        for (final operation in operations) {
          final result = response.resultFor(operation.operationId);
          if (result == null) {
            await _recordFailure(
              operation,
              message: 'Remote response omitted this operation.',
              attemptedAt: now,
              retryable: true,
              accumulator: accumulator,
            );
            continue;
          }
          await _applyResult(
            operation,
            result,
            attemptedAt: now,
            accumulator: accumulator,
          );
        }
      } on SyncAuthenticationException {
        accumulator.authenticationRequired = true;
        break;
      } on SyncTransportException catch (error) {
        for (final operation in operations) {
          await _recordFailure(
            operation,
            message: error.message,
            attemptedAt: now,
            retryable: true,
            accumulator: accumulator,
          );
        }
      }
    }

    return accumulator.toSummary();
  }

  Future<void> _applyResult(
    SyncOutboxItem operation,
    SyncRemoteResult result, {
    required DateTime attemptedAt,
    required _SyncAccumulator accumulator,
  }) async {
    switch (result.outcome) {
      case SyncRemoteOutcome.accepted:
        await _acknowledge(
          operation,
          SyncAcknowledgement.accepted,
          attemptedAt: attemptedAt,
          remoteRevision: result.remoteRevision,
          accumulator: accumulator,
        );
      case SyncRemoteOutcome.duplicate:
        accumulator.duplicates++;
        await _acknowledge(
          operation,
          SyncAcknowledgement.duplicate,
          attemptedAt: attemptedAt,
          remoteRevision: result.remoteRevision,
          accumulator: accumulator,
        );
      case SyncRemoteOutcome.superseded:
        accumulator.superseded++;
        await _acknowledge(
          operation,
          SyncAcknowledgement.superseded,
          attemptedAt: attemptedAt,
          remoteRevision: result.remoteRevision,
          accumulator: accumulator,
        );
      case SyncRemoteOutcome.retryableFailure:
        await _recordFailure(
          operation,
          message: result.message ?? 'Remote requested a retry.',
          attemptedAt: attemptedAt,
          retryable: true,
          accumulator: accumulator,
        );
      case SyncRemoteOutcome.rejected:
        await _recordFailure(
          operation,
          message: result.message ?? 'Remote permanently rejected operation.',
          attemptedAt: attemptedAt,
          retryable: false,
          accumulator: accumulator,
        );
    }
  }

  Future<void> _acknowledge(
    SyncOutboxItem operation,
    SyncAcknowledgement acknowledgement, {
    required DateTime attemptedAt,
    required int? remoteRevision,
    required _SyncAccumulator accumulator,
  }) async {
    await _outboxRepository.markSynced(
      operation.operationId,
      syncedAt: attemptedAt,
      acknowledgement: acknowledgement,
      remoteRevision: remoteRevision,
    );
    accumulator.acknowledged++;
  }

  Future<void> _recordFailure(
    SyncOutboxItem operation, {
    required String message,
    required DateTime attemptedAt,
    required bool retryable,
    required _SyncAccumulator accumulator,
  }) async {
    final attemptsAfterFailure = operation.attempts + 1;
    final deadLetter =
        !retryable || _retryPolicy.shouldDeadLetter(attemptsAfterFailure);
    final nextAttemptAt = deadLetter
        ? null
        : attemptedAt.add(_retryPolicy.delayForAttempt(attemptsAfterFailure));
    await _outboxRepository.markAttemptFailed(
      operation.operationId,
      message,
      attemptedAt: attemptedAt,
      nextAttemptAt: nextAttemptAt,
      deadLetter: deadLetter,
    );
    if (deadLetter) {
      accumulator.deadLettered++;
    } else {
      accumulator.retryScheduled++;
    }
  }

  DateTime _utcNow() {
    final value = _now();
    return value.isUtc ? value : value.toUtc();
  }
}

class _SyncAccumulator {
  bool authenticationRequired = false;
  int batches = 0;
  int attempted = 0;
  int acknowledged = 0;
  int duplicates = 0;
  int superseded = 0;
  int retryScheduled = 0;
  int deadLettered = 0;
  int pruned = 0;

  SyncRunSummary toSummary() => SyncRunSummary(
    authenticationRequired: authenticationRequired,
    batches: batches,
    attempted: attempted,
    acknowledged: acknowledged,
    duplicates: duplicates,
    superseded: superseded,
    retryScheduled: retryScheduled,
    deadLettered: deadLettered,
    pruned: pruned,
  );
}
