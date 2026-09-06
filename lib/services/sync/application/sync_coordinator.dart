import 'dart:async';

import 'package:exam_coach/services/sync/application/sync_worker.dart';
import 'package:exam_coach/services/sync/domain/connectivity_monitor.dart';
import 'package:exam_coach/services/sync/domain/sync_run_summary.dart';

typedef SyncCoordinatorErrorHandler =
    void Function(Object error, StackTrace stackTrace);

class SyncCoordinator {
  factory SyncCoordinator({
    required ConnectivityMonitor connectivityMonitor,
    required SyncRunner syncRunner,
    SyncCoordinatorErrorHandler? onError,
  }) => SyncCoordinator._(connectivityMonitor, syncRunner, onError);

  SyncCoordinator._(this._connectivityMonitor, this._syncRunner, this._onError);

  final ConnectivityMonitor _connectivityMonitor;
  final SyncRunner _syncRunner;
  final SyncCoordinatorErrorHandler? _onError;

  StreamSubscription<bool>? _subscription;

  Future<void> start() async {
    if (_subscription != null) {
      return;
    }
    _subscription = _connectivityMonitor.onStatusChanged.listen((isOnline) {
      if (isOnline) {
        unawaited(_runSafely());
      }
    });
    await _runSafely();
  }

  Future<SyncRunSummary> syncNow() => _syncRunner.runUntilIdle();

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _runSafely() async {
    try {
      await syncNow();
    } on Object catch (error, stackTrace) {
      _onError?.call(error, stackTrace);
    }
  }
}
