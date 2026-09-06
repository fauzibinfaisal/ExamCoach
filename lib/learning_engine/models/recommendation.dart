enum RecommendationType { adaptiveDrill }

enum RecommendationReasonCode {
  repeatedLowAccuracy,
  needsMoreEvidence,
  maintainStrength,
}

class LearningRecommendation {
  const LearningRecommendation({
    required this.type,
    required this.targetTaxonomyId,
    required this.targetLabel,
    required this.priority,
    required this.reasonCode,
    required this.reason,
    required this.expectedBenefit,
    required this.estimatedEffort,
    required this.confidence,
    this.algorithmVersion = 'recommendation_v1',
  });

  final RecommendationType type;
  final String targetTaxonomyId;
  final String targetLabel;
  final int priority;
  final RecommendationReasonCode reasonCode;
  final String reason;
  final String expectedBenefit;
  final Duration estimatedEffort;
  final double confidence;
  final String algorithmVersion;
}
