import 'package:exam_coach/learning_engine/models/recommendation.dart';
import 'package:exam_coach/learning_engine/models/weakness_profile.dart';
import 'package:exam_coach/learning_engine/recommendation_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = RecommendationEngine();

  test('targets highest confidence-weighted need and explains why', () {
    const profiles = [
      WeaknessProfile(
        taxonomyNodeId: 'ratio',
        taxonomyLabel: 'Ratio',
        weaknessScore: 0.8,
        confidence: 0.8,
        sampleSize: 4,
        trend: PerformanceTrend.stable,
        tier: WeaknessTier.weak,
        evidence: [],
      ),
      WeaknessProfile(
        taxonomyNodeId: 'sequence',
        taxonomyLabel: 'Sequence',
        weaknessScore: 0.9,
        confidence: 0.2,
        sampleSize: 1,
        trend: PerformanceTrend.insufficientData,
        tier: WeaknessTier.medium,
        evidence: [],
      ),
    ];

    final recommendation = engine.generate(profiles)!;

    expect(recommendation.targetTaxonomyId, 'ratio');
    expect(recommendation.type, RecommendationType.adaptiveDrill);
    expect(
      recommendation.reasonCode,
      RecommendationReasonCode.repeatedLowAccuracy,
    );
    expect(recommendation.reason, contains('muncul berulang'));
    expect(recommendation.estimatedEffort, const Duration(minutes: 8));
  });

  test('returns no recommendation without performance evidence', () {
    expect(engine.generate(const []), isNull);
  });
}
