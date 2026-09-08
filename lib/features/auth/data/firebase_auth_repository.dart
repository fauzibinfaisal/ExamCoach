import 'package:exam_coach/features/auth/domain/auth_repository.dart';
import 'package:exam_coach/features/auth/domain/auth_user.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth);

  final firebase_auth.FirebaseAuth _auth;

  @override
  bool get isAvailable => true;

  @override
  String? get unavailableReason => null;

  @override
  AuthUser? get currentUser => _mapUser(_auth.currentUser);

  @override
  Stream<AuthUser?> get authStateChanges =>
      _auth.authStateChanges().map(_mapUser);

  @override
  Future<void> register({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on firebase_auth.FirebaseAuthException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on firebase_auth.FirebaseAuthException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on firebase_auth.FirebaseAuthException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  static AuthUser? _mapUser(firebase_auth.User? user) => user == null
      ? null
      : AuthUser(
          uid: user.uid,
          email: user.email,
          emailVerified: user.emailVerified,
        );

  static AuthFailure _failure(firebase_auth.FirebaseAuthException error) {
    final message = switch (error.code) {
      'email-already-in-use' => 'Email ini sudah terdaftar.',
      'invalid-email' => 'Format email tidak valid.',
      'invalid-credential' ||
      'user-not-found' ||
      'wrong-password' => 'Email atau kata sandi tidak cocok.',
      'weak-password' => 'Kata sandi belum memenuhi persyaratan keamanan.',
      'too-many-requests' =>
        'Terlalu banyak percobaan. Tunggu sebentar lalu coba lagi.',
      'network-request-failed' =>
        'Jaringan tidak tersedia. Data belajar lokal tetap aman.',
      _ => error.message ?? 'Autentikasi Firebase gagal.',
    };
    return AuthFailure(error.code, message);
  }
}
