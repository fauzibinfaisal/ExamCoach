import 'package:exam_coach/features/auth/domain/auth_user.dart';

abstract interface class AuthRepository {
  bool get isAvailable;

  String? get unavailableReason;

  AuthUser? get currentUser;

  Stream<AuthUser?> get authStateChanges;

  Future<void> register({required String email, required String password});

  Future<void> signIn({required String email, required String password});

  Future<void> sendPasswordResetEmail(String email);

  Future<void> signOut();
}

class AuthFailure implements Exception {
  const AuthFailure(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class UnavailableAuthRepository implements AuthRepository {
  const UnavailableAuthRepository(this.reason);

  final String reason;

  @override
  bool get isAvailable => false;

  @override
  String? get unavailableReason => reason;

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> get authStateChanges => Stream.value(null);

  @override
  Future<void> register({required String email, required String password}) =>
      _fail();

  @override
  Future<void> signIn({required String email, required String password}) =>
      _fail();

  @override
  Future<void> sendPasswordResetEmail(String email) => _fail();

  @override
  Future<void> signOut() async {}

  Future<void> _fail() =>
      Future.error(AuthFailure('firebase_unavailable', reason));
}
