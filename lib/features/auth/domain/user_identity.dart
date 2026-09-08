class UserIdentity {
  UserIdentity({String? boundUserId})
    : _dataOwnerId = boundUserId ?? localUserId;

  static const localUserId = 'local_user';

  String _dataOwnerId;
  String? _authenticatedUserId;

  String get dataOwnerId => _dataOwnerId;

  String? get authenticatedUserId => _authenticatedUserId;

  bool get isAuthenticated => _authenticatedUserId != null;

  void bindAuthenticatedUser(String uid) {
    _dataOwnerId = uid;
    _authenticatedUserId = uid;
  }

  void clearAuthentication() {
    _authenticatedUserId = null;
  }
}
