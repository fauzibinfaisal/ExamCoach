import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:exam_coach/features/learning/data/local_learning_persistence_repository.dart';
import 'package:exam_coach/services/database/exam_coach_database.dart';
import 'package:exam_coach/services/sync/application/sync_worker.dart';
import 'package:exam_coach/services/sync/domain/connectivity_monitor.dart';
import 'package:exam_coach/services/sync/domain/sync_outbox_item.dart';
import 'package:exam_coach/services/sync/domain/sync_remote_gateway.dart';
import 'package:exam_coach/services/sync/domain/sync_retry_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path_util;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'exam_coach_sync_test_',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('keeps work offline then acknowledges it after reconnect', () async {
    final harness = await _openHarness(temporaryDirectory);
    addTearDown(harness.database.close);
    await _insertOperation(harness.database, 'operation_1');
    final connectivity = _FakeConnectivityMonitor(isOnline: false);
    final gateway = _FakeRemoteGateway((operations, call) {
      return SyncBatchResponse([
        for (final operation in operations)
          SyncRemoteResult(
            operationId: operation.operationId,
            outcome: SyncRemoteOutcome.accepted,
            remoteRevision: 11,
          ),
      ]);
    });
    final worker = SyncWorker(
      outboxRepository: harness.repository,
      remoteGateway: gateway,
      connectivityMonitor: connectivity,
      now: () => DateTime.utc(2026, 9, 6, 12),
    );

    final offline = await worker.runUntilIdle();
    expect(offline.skippedOffline, isTrue);
    expect(gateway.calls, 0);
    expect(await harness.repository.getPending(), hasLength(1));

    connectivity.online = true;
    final online = await worker.runUntilIdle();
    expect(online.attempted, 1);
    expect(online.acknowledged, 1);
    expect(await harness.repository.getPending(), isEmpty);

    final row = await _operationRow(harness.database, 'operation_1');
    expect(row['status'], SyncOutboxStatus.synced.name);
    expect(row['acknowledgement'], SyncAcknowledgement.accepted.name);
    expect(row['remote_revision'], 11);
  });

  test('coalesces concurrent triggers into one in-flight run', () async {
    final harness = await _openHarness(temporaryDirectory);
    addTearDown(harness.database.close);
    await _insertOperation(harness.database, 'single_flight');
    final gateway = _BlockingRemoteGateway();
    final worker = SyncWorker(
      outboxRepository: harness.repository,
      remoteGateway: gateway,
      connectivityMonitor: _FakeConnectivityMonitor(isOnline: true),
      now: () => DateTime.utc(2026, 9, 6, 12),
    );

    final first = worker.runUntilIdle();
    final second = worker.runUntilIdle();
    expect(identical(first, second), isTrue);
    await gateway.started.future;
    expect(gateway.calls, 1);

    gateway.response.complete(
      SyncBatchResponse(const [
        SyncRemoteResult(
          operationId: 'single_flight',
          outcome: SyncRemoteOutcome.accepted,
        ),
      ]),
    );
    final summaries = await Future.wait([first, second]);

    expect(summaries.first.acknowledged, 1);
    expect(summaries.last.acknowledged, 1);
    expect(gateway.calls, 1);
  });

  test(
    'processes accepted, duplicate, and superseded results in batches',
    () async {
      final harness = await _openHarness(temporaryDirectory);
      addTearDown(harness.database.close);
      final createdAt = DateTime.utc(2026, 9, 6, 12);
      await _insertOperation(
        harness.database,
        'accepted',
        createdAt: createdAt,
      );
      await _insertOperation(
        harness.database,
        'duplicate',
        createdAt: createdAt.add(const Duration(seconds: 1)),
      );
      await _insertOperation(
        harness.database,
        'superseded',
        createdAt: createdAt.add(const Duration(seconds: 2)),
      );
      final outcomes = {
        'accepted': SyncRemoteOutcome.accepted,
        'duplicate': SyncRemoteOutcome.duplicate,
        'superseded': SyncRemoteOutcome.superseded,
      };
      final gateway = _FakeRemoteGateway((operations, call) {
        return SyncBatchResponse([
          for (final operation in operations)
            SyncRemoteResult(
              operationId: operation.operationId,
              outcome: outcomes[operation.operationId]!,
              remoteRevision: call,
            ),
        ]);
      });
      final worker = SyncWorker(
        outboxRepository: harness.repository,
        remoteGateway: gateway,
        connectivityMonitor: _FakeConnectivityMonitor(isOnline: true),
        batchSize: 2,
        now: () => createdAt.add(const Duration(minutes: 1)),
      );

      final summary = await worker.runUntilIdle();

      expect(summary.batches, 2);
      expect(summary.attempted, 3);
      expect(summary.acknowledged, 3);
      expect(summary.duplicates, 1);
      expect(summary.superseded, 1);
      expect(gateway.batchSizes, [2, 1]);
      expect(
        (await _operationRow(harness.database, 'duplicate'))['acknowledgement'],
        SyncAcknowledgement.duplicate.name,
      );
      expect(
        (await _operationRow(
          harness.database,
          'superseded',
        ))['acknowledgement'],
        SyncAcknowledgement.superseded.name,
      );
    },
  );

  test(
    'uses exponential backoff then dead-letters repeated failures',
    () async {
      final harness = await _openHarness(temporaryDirectory);
      addTearDown(harness.database.close);
      var now = DateTime.utc(2026, 9, 6, 12);
      await _insertOperation(harness.database, 'retry_me', createdAt: now);
      final gateway = _FakeRemoteGateway((operations, call) {
        return SyncBatchResponse([
          for (final operation in operations)
            SyncRemoteResult(
              operationId: operation.operationId,
              outcome: SyncRemoteOutcome.retryableFailure,
              message: 'temporary outage',
            ),
        ]);
      });
      final worker = SyncWorker(
        outboxRepository: harness.repository,
        remoteGateway: gateway,
        connectivityMonitor: _FakeConnectivityMonitor(isOnline: true),
        retryPolicy: const SyncRetryPolicy(
          maxAttempts: 3,
          initialDelay: Duration(seconds: 5),
          maxDelay: Duration(minutes: 1),
        ),
        now: () => now,
      );

      var summary = await worker.runUntilIdle();
      expect(summary.retryScheduled, 1);
      var pending = (await harness.repository.getPending()).single;
      expect(pending.attempts, 1);
      expect(pending.nextAttemptAt, now.add(const Duration(seconds: 5)));

      summary = await worker.runUntilIdle();
      expect(summary.attempted, 0);
      expect(gateway.calls, 1);

      now = now.add(const Duration(seconds: 5));
      summary = await worker.runUntilIdle();
      expect(summary.retryScheduled, 1);
      pending = (await harness.repository.getPending()).single;
      expect(pending.attempts, 2);
      expect(pending.nextAttemptAt, now.add(const Duration(seconds: 10)));

      now = now.add(const Duration(seconds: 10));
      summary = await worker.runUntilIdle();
      expect(summary.deadLettered, 1);
      expect(await harness.repository.getPending(), isEmpty);
      final row = await _operationRow(harness.database, 'retry_me');
      expect(row['status'], SyncOutboxStatus.deadLetter.name);
      expect(row['attempts'], 3);
      expect(row['next_attempt_at'], isNull);
      expect(row['dead_lettered_at'], now.toIso8601String());
    },
  );

  test('retries an uncertain transport result safely as a duplicate', () async {
    final harness = await _openHarness(temporaryDirectory);
    addTearDown(harness.database.close);
    var now = DateTime.utc(2026, 9, 6, 12);
    await _insertOperation(harness.database, 'uncertain', createdAt: now);
    final gateway = _FakeRemoteGateway((operations, call) {
      if (call == 1) {
        throw const SyncTransportException('connection closed after upload');
      }
      return SyncBatchResponse([
        SyncRemoteResult(
          operationId: operations.single.operationId,
          outcome: SyncRemoteOutcome.duplicate,
          remoteRevision: 3,
        ),
      ]);
    });
    final worker = SyncWorker(
      outboxRepository: harness.repository,
      remoteGateway: gateway,
      connectivityMonitor: _FakeConnectivityMonitor(isOnline: true),
      retryPolicy: const SyncRetryPolicy(initialDelay: Duration(seconds: 2)),
      now: () => now,
    );

    expect((await worker.runUntilIdle()).retryScheduled, 1);
    now = now.add(const Duration(seconds: 2));
    final summary = await worker.runUntilIdle();

    expect(summary.acknowledged, 1);
    expect(summary.duplicates, 1);
    final row = await _operationRow(harness.database, 'uncertain');
    expect(row['status'], SyncOutboxStatus.synced.name);
    expect(row['attempts'], 1);
    expect(row['acknowledgement'], SyncAcknowledgement.duplicate.name);
  });

  test(
    'dead-letters rejection and retries a missing acknowledgement',
    () async {
      final harness = await _openHarness(temporaryDirectory);
      addTearDown(harness.database.close);
      final now = DateTime.utc(2026, 9, 6, 12);
      await _insertOperation(harness.database, 'rejected', createdAt: now);
      await _insertOperation(
        harness.database,
        'omitted',
        createdAt: now.add(const Duration(seconds: 1)),
      );
      final worker = SyncWorker(
        outboxRepository: harness.repository,
        remoteGateway: _FakeRemoteGateway((operations, call) {
          return SyncBatchResponse(const [
            SyncRemoteResult(
              operationId: 'rejected',
              outcome: SyncRemoteOutcome.rejected,
              message: 'invalid payload',
            ),
          ]);
        }),
        connectivityMonitor: _FakeConnectivityMonitor(isOnline: true),
        now: () => now.add(const Duration(minutes: 1)),
      );

      final summary = await worker.runUntilIdle();

      expect(summary.deadLettered, 1);
      expect(summary.retryScheduled, 1);
      expect(
        (await _operationRow(harness.database, 'rejected'))['status'],
        SyncOutboxStatus.deadLetter.name,
      );
      final omitted = (await harness.repository.getPending()).single;
      expect(omitted.operationId, 'omitted');
      expect(omitted.attempts, 1);
      expect(omitted.lastError, contains('omitted'));
    },
  );

  test('prunes old acknowledged analytics but retains dead letters', () async {
    final harness = await _openHarness(temporaryDirectory);
    addTearDown(harness.database.close);
    final now = DateTime.utc(2026, 9, 20, 12);
    final database = await harness.database.instance;
    await database.insert('analytics_events', {
      'id': 'old_event',
      'event_name': 'question_answered',
      'event_version': 1,
      'occurred_at': now.subtract(const Duration(days: 10)).toIso8601String(),
      'user_id': 'local_user',
      'session_id': null,
      'properties_json': '{}',
      'upload_status': SyncOutboxStatus.synced.name,
    });
    await _insertOperation(
      harness.database,
      'analytics:old_event',
      entityType: 'analytics_event',
      entityId: 'old_event',
      createdAt: now.subtract(const Duration(days: 10)),
      status: SyncOutboxStatus.synced,
      syncedAt: now.subtract(const Duration(days: 9)),
      acknowledgement: SyncAcknowledgement.accepted,
    );
    await _insertOperation(
      harness.database,
      'dead_letter',
      createdAt: now.subtract(const Duration(days: 30)),
      status: SyncOutboxStatus.deadLetter,
      deadLetteredAt: now.subtract(const Duration(days: 29)),
    );
    final worker = SyncWorker(
      outboxRepository: harness.repository,
      remoteGateway: _FakeRemoteGateway((operations, call) {
        return SyncBatchResponse(const []);
      }),
      connectivityMonitor: _FakeConnectivityMonitor(isOnline: true),
      syncedRetention: const Duration(days: 7),
      now: () => now,
    );

    final summary = await worker.runUntilIdle();

    expect(summary.pruned, 1);
    expect(await database.query('analytics_events'), isEmpty);
    expect(
      (await database.query('sync_outbox')).single['status'],
      SyncOutboxStatus.deadLetter.name,
    );
  });
}

Future<_SyncHarness> _openHarness(Directory directory) async {
  final database = ExamCoachDatabase(
    databasePath: path_util.join(directory.path, 'sync_test.sqlite'),
    factory: databaseFactoryFfi,
  );
  await database.instance;
  return _SyncHarness(
    database: database,
    repository: LocalLearningPersistenceRepository(database),
  );
}

Future<void> _insertOperation(
  ExamCoachDatabase database,
  String operationId, {
  String entityType = 'exam_session',
  String? entityId,
  DateTime? createdAt,
  SyncOutboxStatus status = SyncOutboxStatus.pending,
  DateTime? syncedAt,
  DateTime? deadLetteredAt,
  SyncAcknowledgement? acknowledgement,
}) async {
  final opened = await database.instance;
  await opened.insert('sync_outbox', {
    'operation_id': operationId,
    'entity_type': entityType,
    'entity_id': entityId ?? operationId,
    'operation': 'upsert',
    'payload_json': jsonEncode({'operationId': operationId}),
    'created_at': (createdAt ?? DateTime.utc(2026, 9, 6)).toIso8601String(),
    'attempts': 0,
    'status': status.name,
    'last_error': null,
    'last_attempt_at': null,
    'next_attempt_at': null,
    'synced_at': syncedAt?.toIso8601String(),
    'dead_lettered_at': deadLetteredAt?.toIso8601String(),
    'acknowledgement': acknowledgement?.name,
    'remote_revision': null,
  });
}

Future<Map<String, Object?>> _operationRow(
  ExamCoachDatabase database,
  String operationId,
) async {
  final opened = await database.instance;
  return (await opened.query(
    'sync_outbox',
    where: 'operation_id = ?',
    whereArgs: [operationId],
  )).single;
}

class _SyncHarness {
  const _SyncHarness({required this.database, required this.repository});

  final ExamCoachDatabase database;
  final LocalLearningPersistenceRepository repository;
}

class _FakeConnectivityMonitor implements ConnectivityMonitor {
  _FakeConnectivityMonitor({required bool isOnline}) : online = isOnline;

  bool online;

  @override
  Future<bool> get isOnline async => online;

  @override
  Stream<bool> get onStatusChanged => const Stream.empty();
}

typedef _RemoteResponder =
    SyncBatchResponse Function(List<SyncOutboxItem> operations, int call);

class _FakeRemoteGateway implements SyncRemoteGateway {
  _FakeRemoteGateway(this._responder);

  final _RemoteResponder _responder;
  final List<int> batchSizes = [];

  int get calls => batchSizes.length;

  @override
  Future<SyncBatchResponse> pushBatch(List<SyncOutboxItem> operations) async {
    batchSizes.add(operations.length);
    return _responder(operations, calls);
  }
}

class _BlockingRemoteGateway implements SyncRemoteGateway {
  final Completer<void> started = Completer<void>();
  final Completer<SyncBatchResponse> response = Completer<SyncBatchResponse>();
  int calls = 0;

  @override
  Future<SyncBatchResponse> pushBatch(List<SyncOutboxItem> operations) {
    calls++;
    if (!started.isCompleted) {
      started.complete();
    }
    return response.future;
  }
}
