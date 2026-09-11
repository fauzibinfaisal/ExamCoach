import 'package:exam_coach/features/auth/application/auth_cubit.dart';
import 'package:exam_coach/features/auth/application/auth_state.dart';
import 'package:exam_coach/features/subscription/application/subscription_cubit.dart';
import 'package:exam_coach/features/subscription/application/subscription_state.dart';
import 'package:exam_coach/features/subscription/domain/subscription_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cubit = context.read<SubscriptionCubit>();
      cubit.recordPaywallViewed();
      cubit.refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthCubit, AuthState>(
      listener: (_, _) => context.read<SubscriptionCubit>().refresh(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Paket ExamCoach')),
        body: SafeArea(
          top: false,
          child: BlocBuilder<SubscriptionCubit, SubscriptionState>(
            builder: (context, state) => ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              children: [
                Text(
                  'Belajar lebih dalam, tetap terukur.',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Harga dan periode selalu berasal dari toko. Akses premium baru berlaku setelah entitlement diverifikasi backend.',
                ),
                const SizedBox(height: 20),
                _CurrentPlan(entitlement: state.entitlement),
                const SizedBox(height: 16),
                if (state.message case final message?) ...[
                  _Notice(
                    message: message,
                    isError: state.status == SubscriptionViewStatus.failure,
                  ),
                  const SizedBox(height: 16),
                ],
                if (state.status == SubscriptionViewStatus.signedOut)
                  FilledButton.icon(
                    onPressed: () => context.push('/account'),
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Masuk ke akun'),
                  )
                else ...[
                  for (final package in state.packages) ...[
                    _PackageCard(
                      package: package,
                      enabled: state.status != SubscriptionViewStatus.loading,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (state.status == SubscriptionViewStatus.loading)
                    const Center(child: CircularProgressIndicator())
                  else if (state.status == SubscriptionViewStatus.failure ||
                      state.status == SubscriptionViewStatus.cancelled)
                    OutlinedButton.icon(
                      onPressed: context.read<SubscriptionCubit>().refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Muat ulang paket'),
                    ),
                  const SizedBox(height: 10),
                  TextButton(
                    key: const Key('restore-purchases-button'),
                    onPressed:
                        state.status == SubscriptionViewStatus.loading ||
                            state.status == SubscriptionViewStatus.unavailable
                        ? null
                        : context.read<SubscriptionCubit>().restore,
                    child: const Text('Pulihkan pembelian'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrentPlan extends StatelessWidget {
  const _CurrentPlan({required this.entitlement});

  final TrustedEntitlement? entitlement;

  @override
  Widget build(BuildContext context) {
    final value = entitlement;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4F5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user_outlined, color: Color(0xFF20566B)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value == null
                  ? 'Paket saat ini belum diverifikasi'
                  : 'Paket terverifikasi: ${value.planId}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({required this.package, required this.enabled});

  final SubscriptionPackage package;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(package.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(package.description),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    package.price,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                FilledButton(
                  key: Key('purchase-${package.packageId}'),
                  onPressed: enabled
                      ? () => context.read<SubscriptionCubit>().purchase(
                          package.packageId,
                        )
                      : null,
                  child: const Text('Pilih'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError
            ? Theme.of(context).colorScheme.errorContainer
            : const Color(0xFFFFF7E7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(message),
    );
  }
}
