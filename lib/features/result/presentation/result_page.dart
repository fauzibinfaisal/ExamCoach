import 'package:exam_coach/features/exam/domain/models/exam_session.dart';
import 'package:exam_coach/features/learning/application/learning_flow_cubit.dart';
import 'package:exam_coach/features/learning/application/learning_flow_state.dart';
import 'package:exam_coach/learning_engine/models/recommendation.dart';
import 'package:exam_coach/learning_engine/models/weakness_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class ResultPage extends StatelessWidget {
  const ResultPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LearningFlowCubit, LearningFlowState>(
      builder: (context, state) {
        final score = state.latestScore;
        if (state.status != LearningFlowStatus.result || score == null) {
          return Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('Kembali ke beranda'),
              ),
            ),
          );
        }

        final isDrillResult = state.mode == ExamSessionMode.adaptiveDrill;
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Text('Hasil belajar'),
          ),
          body: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              children: [
                Text(
                  isDrillResult ? 'Insight diperbarui' : 'Tryout selesai',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  isDrillResult
                      ? 'Jawaban drill sudah masuk ke profil performamu.'
                      : 'Ini bukan sekadar nilai—berikut area yang paling berguna untuk dilatih.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                _ScoreCard(
                  score: score.percentage,
                  correct: score.correct,
                  total: score.total,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('review-answers-button'),
                  onPressed: () => context.go('/answer-review'),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Tinjau jawaban & pembahasan'),
                ),
                const SizedBox(height: 26),
                Text(
                  'Analisis area belajar',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                for (final profile in state.profiles) ...[
                  _WeaknessCard(
                    profile: profile,
                    previous: _previousFor(
                      state.previousProfiles,
                      profile.taxonomyNodeId,
                    ),
                    showTrend: isDrillResult,
                  ),
                  const SizedBox(height: 10),
                ],
                if (state.recommendation case final recommendation?) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Rekomendasi berikutnya',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _RecommendationCard(recommendation: recommendation),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    key: const Key('start-drill-button'),
                    onPressed: state.isSaving
                        ? null
                        : () async {
                            final started = await context
                                .read<LearningFlowCubit>()
                                .startRecommendedDrill();
                            if (started && context.mounted) {
                              context.go('/session');
                            }
                          },
                    icon: const Icon(Icons.track_changes_rounded),
                    label: Text(
                      isDrillResult
                          ? 'Lanjutkan drill adaptif'
                          : 'Mulai drill rekomendasi',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Kembali ke beranda'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static WeaknessProfile? _previousFor(
    List<WeaknessProfile> profiles,
    String id,
  ) {
    for (final profile in profiles) {
      if (profile.taxonomyNodeId == id) {
        return profile;
      }
    }
    return null;
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({
    required this.score,
    required this.correct,
    required this.total,
  });

  final int score;
  final int correct;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            SizedBox(
              width: 86,
              height: 86,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 9,
                    backgroundColor: const Color(0xFFE7EDF1),
                  ),
                  Text(
                    '$score',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 22),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Skor sesi',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$correct dari $total benar',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Dihitung lokal tanpa AI',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeaknessCard extends StatelessWidget {
  const _WeaknessCard({
    required this.profile,
    required this.previous,
    required this.showTrend,
  });

  final WeaknessProfile profile;
  final WeaknessProfile? previous;
  final bool showTrend;

  @override
  Widget build(BuildContext context) {
    final severity = (profile.weaknessScore * 100).round();
    final tierLabel = switch (profile.tier) {
      WeaknessTier.weak => 'Prioritas',
      WeaknessTier.medium => 'Perlu dipantau',
      WeaknessTier.strong => 'Kuat',
    };
    final tierColor = switch (profile.tier) {
      WeaknessTier.weak => const Color(0xFFB5473C),
      WeaknessTier.medium => const Color(0xFF9A6700),
      WeaknessTier.strong => const Color(0xFF147D78),
    };
    final improvement = previous == null
        ? null
        : ((previous!.weaknessScore - profile.weaknessScore) * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    profile.taxonomyLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: tierColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    tierLabel,
                    style: TextStyle(
                      color: tierColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: profile.weaknessScore,
                minHeight: 8,
                backgroundColor: const Color(0xFFE7EDF1),
                color: tierColor,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              'Skor kelemahan $severity% • Keyakinan ${(profile.confidence * 100).round()}% • ${profile.sampleSize} jawaban',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (showTrend && improvement != null) ...[
              const SizedBox(height: 8),
              Text(
                improvement > 0
                    ? 'Membaik $improvement poin setelah data terbaru.'
                    : improvement < 0
                    ? 'Perlu perhatian: kelemahan bertambah ${improvement.abs()} poin.'
                    : 'Stabil dibanding sebelum drill.',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: improvement > 0
                      ? const Color(0xFF147D78)
                      : const Color(0xFF526675),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.recommendation});

  final LearningRecommendation recommendation;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF17324D), Color(0xFF20566B)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome_rounded, color: Color(0xFF74D7CF)),
          const SizedBox(height: 14),
          Text(
            'Fokus ${recommendation.targetLabel}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            recommendation.reason,
            style: const TextStyle(color: Color(0xFFD7E5EC), height: 1.5),
          ),
          const SizedBox(height: 12),
          Text(
            'Estimasi ${recommendation.estimatedEffort.inMinutes} menit • Keyakinan ${(recommendation.confidence * 100).round()}%',
            style: const TextStyle(
              color: Color(0xFF9CCACB),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
