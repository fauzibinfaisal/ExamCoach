import 'package:exam_coach/features/auth/application/auth_cubit.dart';
import 'package:exam_coach/features/auth/application/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _registerMode = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Akun & sinkronisasi')),
      body: SafeArea(
        child: BlocBuilder<AuthCubit, AuthState>(
          builder: (context, state) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Pulihkan progres di perangkat lain',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(
                  'Belajar tetap berjalan offline. Setelah masuk, data lokal pertama kali diklaim oleh akun dan outbox dikirim secara aman saat jaringan tersedia.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                if (state.status == AuthStatus.unavailable)
                  _UnavailableCard(message: state.message)
                else if (state.isAuthenticated)
                  _SignedInCard(state: state)
                else
                  _CredentialForm(
                    state: state,
                    emailController: _emailController,
                    passwordController: _passwordController,
                    registerMode: _registerMode,
                    obscurePassword: _obscurePassword,
                    onToggleMode: () =>
                        setState(() => _registerMode = !_registerMode),
                    onTogglePassword: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.cloud_off_rounded),
                SizedBox(width: 10),
                Text(
                  'Firebase belum aktif',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(message ?? 'Konfigurasi Firebase belum tersedia.'),
            const SizedBox(height: 10),
            const Text(
              'Aplikasi tetap menyimpan progres di perangkat. Ikuti docs/engineering/Firebase_Integration.md untuk mengaktifkan akun dan sinkronisasi.',
            ),
          ],
        ),
      ),
    );
  }
}

class _SignedInCard extends StatelessWidget {
  const _SignedInCard({required this.state});

  final AuthState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.verified_user_rounded, color: Color(0xFF18794E)),
                SizedBox(width: 10),
                Text(
                  'Akun terhubung',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(state.user?.email ?? state.user!.uid),
            if (state.message case final message?) ...[
              const SizedBox(height: 8),
              Text(message),
            ],
            const SizedBox(height: 18),
            OutlinedButton.icon(
              key: const Key('sign-out-button'),
              onPressed: state.status == AuthStatus.processing
                  ? null
                  : () => context.read<AuthCubit>().signOut(),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Keluar akun'),
            ),
            const SizedBox(height: 8),
            Text(
              'Keluar tidak menghapus data lokal. Perangkat tetap terikat ke akun ini untuk mencegah kebocoran data saat berganti akun.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _CredentialForm extends StatelessWidget {
  const _CredentialForm({
    required this.state,
    required this.emailController,
    required this.passwordController,
    required this.registerMode,
    required this.obscurePassword,
    required this.onToggleMode,
    required this.onTogglePassword,
  });

  final AuthState state;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool registerMode;
  final bool obscurePassword;
  final VoidCallback onToggleMode;
  final VoidCallback onTogglePassword;

  @override
  Widget build(BuildContext context) {
    final processing = state.status == AuthStatus.processing;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              registerMode ? 'Buat akun' : 'Masuk',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('auth-email-field'),
              controller: emailController,
              enabled: !processing,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('auth-password-field'),
              controller: passwordController,
              enabled: !processing,
              obscureText: obscurePassword,
              decoration: InputDecoration(
                labelText: 'Kata sandi',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: onTogglePassword,
                  icon: Icon(
                    obscurePassword
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                ),
              ),
              onSubmitted: processing ? null : (_) => _submit(context),
            ),
            if (state.message case final message?) ...[
              const SizedBox(height: 12),
              Text(
                message,
                style: TextStyle(
                  color: state.isError
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('auth-submit-button'),
              onPressed: processing ? null : () => _submit(context),
              child: Text(
                processing
                    ? 'Memproses…'
                    : registerMode
                    ? 'Daftar'
                    : 'Masuk',
              ),
            ),
            TextButton(
              onPressed: processing ? null : onToggleMode,
              child: Text(
                registerMode
                    ? 'Sudah punya akun? Masuk'
                    : 'Belum punya akun? Daftar',
              ),
            ),
            if (!registerMode)
              TextButton(
                onPressed: processing
                    ? null
                    : () => context.read<AuthCubit>().sendPasswordResetEmail(
                        emailController.text,
                      ),
                child: const Text('Lupa kata sandi'),
              ),
          ],
        ),
      ),
    );
  }

  void _submit(BuildContext context) {
    final cubit = context.read<AuthCubit>();
    if (registerMode) {
      cubit.register(emailController.text, passwordController.text);
    } else {
      cubit.signIn(emailController.text, passwordController.text);
    }
  }
}
