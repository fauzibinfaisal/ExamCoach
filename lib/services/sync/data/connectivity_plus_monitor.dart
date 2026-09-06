import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:exam_coach/services/sync/domain/connectivity_monitor.dart';

class ConnectivityPlusMonitor implements ConnectivityMonitor {
  ConnectivityPlusMonitor({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> get isOnline async =>
      _hasNetworkTransport(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get onStatusChanged =>
      _connectivity.onConnectivityChanged.map(_hasNetworkTransport).distinct();

  static bool _hasNetworkTransport(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);
}
