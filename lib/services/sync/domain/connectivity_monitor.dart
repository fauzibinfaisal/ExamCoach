abstract interface class ConnectivityMonitor {
  Future<bool> get isOnline;

  Stream<bool> get onStatusChanged;
}
