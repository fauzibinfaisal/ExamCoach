import 'package:exam_coach/learning_engine/models/recommendation.dart';
import 'package:exam_coach/learning_engine/models/weakness_profile.dart';

class RecommendationEngine {
  const RecommendationEngine();

  LearningRecommendation? generate(List<WeaknessProfile> profiles) {
    if (profiles.isEmpty) {
      return null;
    }

    final target = profiles.reduce((current, next) {
      final currentPriority = current.weaknessScore * current.confidence;
      final nextPriority = next.weaknessScore * next.confidence;
      return nextPriority > currentPriority ? next : current;
    });
    final reasonCode = switch (target.tier) {
      WeaknessTier.weak => RecommendationReasonCode.repeatedLowAccuracy,
      WeaknessTier.medium => RecommendationReasonCode.needsMoreEvidence,
      WeaknessTier.strong => RecommendationReasonCode.maintainStrength,
    };
    final reason = switch (reasonCode) {
      RecommendationReasonCode.repeatedLowAccuracy =>
        'Akurasi pada ${target.taxonomyLabel} masih rendah dan polanya muncul berulang.',
      RecommendationReasonCode.needsMoreEvidence =>
        'Performa ${target.taxonomyLabel} belum konsisten; latihan terarah akan memperjelas pola.',
      RecommendationReasonCode.maintainStrength =>
        'Belum ada kelemahan kuat. Pertahankan ${target.taxonomyLabel} sambil menambah bukti belajar.',
    };

    return LearningRecommendation(
      type: RecommendationType.adaptiveDrill,
      targetTaxonomyId: target.taxonomyNodeId,
      targetLabel: target.taxonomyLabel,
      priority: target.tier == WeaknessTier.weak ? 1 : 2,
      reasonCode: reasonCode,
      reason: reason,
      expectedBenefit:
          'Meningkatkan akurasi dan konsistensi pada area prioritas.',
      estimatedEffort: const Duration(minutes: 8),
      confidence: target.confidence,
    );
  }
}
