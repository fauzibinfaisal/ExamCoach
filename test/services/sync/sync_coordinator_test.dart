import 'dart:async';

import 'package:exam_coach/services/sync/application/sync_coordinator.dart';
import 'package:exam_coach/services/sync/application/sync_worker.dart';
import 'package:exam_coach/services/sync/domain/connectivity_monitor.dart';
import 'package:exam_coach/services/sync/domain/sync_retry_policy.dart';
import 'package:exam_coach/services/sync/domain/sync_run_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exponential retry policy caps delay and enforces attempt limit', () {
    const policy = SyncRetryPolicy(
      maxAttempts: 4,
      initialDelay: Duration(seconds: 5),
      maxDelay: Duration(seconds: 12),
    );

    expect(policy.delayForAttempt(1), const Duration(seconds: 5));
    expect(policy.delayForAttempt(2), const Duration(seconds: 10));
    expect(policy.delayForAttempt(3), const Duration(seconds: 12));
    expect(policy.shouldDeadLetter(3), isFalse);
    expect(policy.shouldDeadLetter(4), isTrue);
  });

  test(
    'coordinator triggers initial and reconnect sync without duplicate subscription',
    () async {
      final connectivity = _ControlledConnectivityMonitor(false);
      final runner = _RecordingSyncRunner();
      final coordinator = SyncCoordinator(
        connectivityMonitor: connectivity,
        syncRunner: runner,
      );
      addTearDown(coordinator.dispose);
      addTearDown(connectivity.dispose);

      await coordinator.start();
      expect(runner.runs, 1);

      connectivity.emit(false);
      await Future<void>.delayed(Duration.zero);
      expect(runner.runs, 1);

      connectivity.emit(true);
      await runner.waitForRuns(2);
      expect(runner.runs, 2);

      await coordinator.start();
      connectivity.emit(true);
      await runner.waitForRuns(3);
      expect(runner.runs, 3);
    },
  );
}

class _ControlledConnectivityMonitor implements ConnectivityMonitor {
  _ControlledConnectivityMonitor(this.online);

  final StreamController<bool> _controller = StreamController.broadcast();
  bool online;

  @override
  Future<bool> get isOnline async => online;

  @override
  Stream<bool> get onStatusChanged => _controller.stream;

  void emit(bool value) {
    online = value;
    _controller.add(value);
  }

  Future<void> dispose() => _controller.close();
}

class _RecordingSyncRunner implements SyncRunner {
  final StreamController<int> _runCounts = StreamController.broadcast();
  int runs = 0;

  @override
  Future<SyncRunSummary> runUntilIdle() async {
    runs++;
    _runCounts.add(runs);
    return const SyncRunSummary();
  }

  Future<void> waitForRuns(int count) async {
    if (runs >= count) {
      return;
    }
    await _runCounts.stream
        .firstWhere((current) => current >= count)
        .timeout(const Duration(seconds: 1));
  }
}
