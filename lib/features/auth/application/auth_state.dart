import 'package:exam_coach/features/auth/domain/auth_user.dart';

enum AuthStatus { unavailable, signedOut, processing, signedIn }

class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.message,
    this.isError = false,
  });

  const AuthState.unavailable(String reason)
    : this(status: AuthStatus.unavailable, message: reason);

  const AuthState.signedOut({String? message, bool isError = false})
    : this(status: AuthStatus.signedOut, message: message, isError: isError);

  final AuthStatus status;
  final AuthUser? user;
  final String? message;
  final bool isError;

  bool get isAuthenticated => status == AuthStatus.signedIn && user != null;
}
