class AuthUser {
  const AuthUser({
    required this.uid,
    required this.email,
    required this.emailVerified,
  });

  final String uid;
  final String? email;
  final bool emailVerified;
}
