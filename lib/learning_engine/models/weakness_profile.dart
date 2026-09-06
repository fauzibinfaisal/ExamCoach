enum WeaknessTier { weak, medium, strong }

enum PerformanceTrend { improving, stable, declining, insufficientData }

class WeaknessProfile {
  const WeaknessProfile({
    required this.taxonomyNodeId,
    required this.taxonomyLabel,
    required this.weaknessScore,
    required this.confidence,
    required this.sampleSize,
    required this.trend,
    required this.tier,
    required this.evidence,
    this.algorithmVersion = 'weakness_v1',
  });

  final String taxonomyNodeId;
  final String taxonomyLabel;
  final double weaknessScore;
  final double confidence;
  final int sampleSize;
  final PerformanceTrend trend;
  final WeaknessTier tier;
  final List<String> evidence;
  final String algorithmVersion;
}
