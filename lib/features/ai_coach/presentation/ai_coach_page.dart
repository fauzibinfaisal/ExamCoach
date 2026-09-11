import 'package:exam_coach/features/ai_coach/application/ai_coach_cubit.dart';
import 'package:exam_coach/features/ai_coach/application/ai_coach_state.dart';
import 'package:exam_coach/features/ai_coach/domain/ai_coach_models.dart';
import 'package:exam_coach/features/auth/application/auth_cubit.dart';
import 'package:exam_coach/features/auth/application/auth_state.dart';
import 'package:exam_coach/features/learning/application/learning_flow_cubit.dart';
import 'package:exam_coach/features/learning/application/learning_flow_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class AiCoachPage extends StatefulWidget {
  const AiCoachPage({super.key});

  @override
  State<AiCoachPage> createState() => _AiCoachPageState();
}

class _AiCoachPageState extends State<AiCoachPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  void _refresh() {
    if (!mounted) return;
    context.read<AiCoachCubit>().refresh(
      context.read<LearningFlowCubit>().state,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<AuthCubit, AuthState>(listener: (_, _) => _refresh()),
        BlocListener<LearningFlowCubit, LearningFlowState>(
          listener: (_, _) => _refresh(),
        ),
        BlocListener<AiCoachCubit, AiCoachState>(
          listenWhen: (previous, current) =>
              previous.insight?.generatedAt != current.insight?.generatedAt,
          listener: (context, state) {
            if (state.insight != null) {
              context.read<AiCoachCubit>().recordViewed();
            }
          },
        ),
      ],
      child: Scaffold(
        appBar: AppBar(title: const Text('AI Coach')),
        body: SafeArea(
          top: false,
          child: BlocBuilder<AiCoachCubit, AiCoachState>(
            builder: (context, state) {
              final learning = context.watch<LearningFlowCubit>().state;
              return ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                children: [
                  Text(
                    'Arahan singkat dari data belajarmu',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'AI hanya menjelaskan hasil yang sudah dihitung oleh learning engine. Nilai dan rekomendasi resmi tidak diubah AI.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  _DeterministicFallbackCard(state: learning),
                  const SizedBox(height: 16),
                  if (state.quota case final quota?) ...[
                    _QuotaCard(quota: quota),
                    const SizedBox(height: 16),
                  ],
                  if (state.message case final message?) ...[
                    _StatusNotice(state: state, message: message),
                    const SizedBox(height: 16),
                  ],
                  if (state.insight case final insight?) ...[
                    _InsightView(insight: insight),
                    const SizedBox(height: 16),
                  ],
                  _ActionArea(state: state, onRefresh: _refresh),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DeterministicFallbackCard extends StatelessWidget {
  const _DeterministicFallbackCard({required this.state});

  final LearningFlowState state;

  @override
  Widget build(BuildContext context) {
    final score = state.latestScore;
    final recommendation = state.recommendation;
    final topWeakness = state.profiles.isEmpty ? null : state.profiles.first;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.verified_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Insight deterministik',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              score == null
                  ? 'Belum ada hasil belajar yang selesai.'
                  : 'Skor terbaru ${score.percentage}. ${topWeakness == null ? '' : 'Area prioritas: ${topWeakness.taxonomyLabel}. '}${recommendation == null ? '' : 'Tindakan berikutnya: ${recommendation.reason}'}',
            ),
          ],
        ),
      ),
    );
  }
}

class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.quota});

  final AiCoachQuotaStatus quota;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4F5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.data_usage_rounded, color: Color(0xFF20566B)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Paket ${quota.planId} • ${quota.remaining}/${quota.dailyLimit} permintaan tersisa hari ini',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusNotice extends StatelessWidget {
  const _StatusNotice({required this.state, required this.message});

  final AiCoachState state;
  final String message;

  @override
  Widget build(BuildContext context) {
    final isError =
        state.status == AiCoachStatus.failure ||
        state.status == AiCoachStatus.quotaExhausted;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError
            ? Theme.of(context).colorScheme.errorContainer
            : const Color(0xFFFFF7E7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.info_outline : Icons.shield_outlined),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _InsightView extends StatelessWidget {
  const _InsightView({required this.insight});

  final AiCoachInsight insight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        insight.fromServerCache
                            ? 'Insight AI tersimpan'
                            : 'Insight AI terbaru',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(insight.summary),
                const SizedBox(height: 16),
                Text(
                  'Area yang perlu dipahami',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(insight.weaknessExplanation),
                const SizedBox(height: 16),
                Text(
                  'Mengapa ini penting',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(insight.whyItMatters),
              ],
            ),
          ),
        ),
        if (insight.studyPlan.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'Rencana belajar',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          for (final item in insight.studyPlan)
            Card(
              child: ListTile(
                leading: const Icon(Icons.checklist_rounded),
                title: Text(item.title),
                subtitle: Text(item.action),
                trailing: Text('${item.durationMinutes} mnt'),
              ),
            ),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF17324D), Color(0xFF20566B)],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            insight.motivation,
            style: const TextStyle(color: Colors.white, height: 1.5),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Provider ${insight.provider} • Model ${insight.model} • ${insight.promptVersion}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ActionArea extends StatelessWidget {
  const _ActionArea({required this.state, required this.onRefresh});

  final AiCoachState state;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    if (state.status == AiCoachStatus.noLearningData) {
      return FilledButton(
        onPressed: () => context.go('/'),
        child: const Text('Mulai dari beranda'),
      );
    }
    if (state.status == AiCoachStatus.signedOut) {
      return FilledButton.icon(
        key: const Key('ai-coach-sign-in-button'),
        onPressed: () => context.push('/account'),
        icon: const Icon(Icons.login_rounded),
        label: const Text('Masuk ke akun'),
      );
    }
    if (state.status == AiCoachStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.status == AiCoachStatus.ready ||
        state.status == AiCoachStatus.success ||
        state.status == AiCoachStatus.failure) {
      final canGenerate =
          state.quota?.canGenerate ?? state.status == AiCoachStatus.failure;
      return FilledButton.icon(
        key: const Key('generate-ai-insight-button'),
        onPressed: canGenerate
            ? () => context.read<AiCoachCubit>().generate()
            : null,
        icon: const Icon(Icons.auto_awesome_rounded),
        label: Text(
          state.hasInsight ? 'Perbarui insight AI' : 'Buat insight AI',
        ),
      );
    }
    if (state.status == AiCoachStatus.unavailable && state.hasInsight) {
      return OutlinedButton.icon(
        onPressed: onRefresh,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Periksa koneksi lagi'),
      );
    }
    return const SizedBox.shrink();
  }
}
