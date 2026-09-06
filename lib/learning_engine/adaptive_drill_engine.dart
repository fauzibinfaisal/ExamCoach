import 'package:exam_coach/features/exam/domain/models/question.dart';
import 'package:exam_coach/learning_engine/models/weakness_profile.dart';

class AdaptiveDrillConfig {
  const AdaptiveDrillConfig({
    this.algorithmVersion = 'adaptive_drill_v1',
    this.weakRatio = 0.70,
    this.mediumRatio = 0.20,
    this.strongRatio = 0.10,
  }) : assert(
         weakRatio + mediumRatio + strongRatio > 0.999 &&
             weakRatio + mediumRatio + strongRatio < 1.001,
       );

  final String algorithmVersion;
  final double weakRatio;
  final double mediumRatio;
  final double strongRatio;
}

class AdaptiveDrillEngine {
  const AdaptiveDrillEngine({this.config = const AdaptiveDrillConfig()});

  final AdaptiveDrillConfig config;

  List<Question> select({
    required List<Question> questions,
    required List<WeaknessProfile> profiles,
    required Set<String> previouslyAttemptedQuestionIds,
    int count = 6,
  }) {
    if (count <= 0 || questions.isEmpty) {
      return const [];
    }

    final profileByTopic = {
      for (final profile in profiles) profile.taxonomyNodeId: profile,
    };
    final pools = <WeaknessTier, List<Question>>{
      for (final tier in WeaknessTier.values) tier: [],
    };

    for (final question in questions) {
      final tier =
          profileByTopic[question.taxonomy.topicId]?.tier ??
          WeaknessTier.medium;
      pools[tier]!.add(question);
    }
    for (final pool in pools.values) {
      pool.sort((a, b) {
        final aAttempted = previouslyAttemptedQuestionIds.contains(a.id)
            ? 1
            : 0;
        final bAttempted = previouslyAttemptedQuestionIds.contains(b.id)
            ? 1
            : 0;
        final exposureComparison = aAttempted.compareTo(bAttempted);
        return exposureComparison != 0
            ? exposureComparison
            : a.id.compareTo(b.id);
      });
    }

    final limit = count.clamp(0, questions.length);
    final quotas = _allocateQuotas(limit);
    final selected = <Question>[];
    final selectedIds = <String>{};

    for (final tier in WeaknessTier.values) {
      for (final question in pools[tier]!.take(quotas[tier]!)) {
        selected.add(question);
        selectedIds.add(question.id);
      }
    }

    if (selected.length < limit) {
      final fallback = [
        ...pools[WeaknessTier.weak]!,
        ...pools[WeaknessTier.medium]!,
        ...pools[WeaknessTier.strong]!,
      ];
      for (final question in fallback) {
        if (selected.length == limit) {
          break;
        }
        if (selectedIds.add(question.id)) {
          selected.add(question);
        }
      }
    }

    return List.unmodifiable(selected);
  }

  Map<WeaknessTier, int> _allocateQuotas(int count) {
    final ratios = <WeaknessTier, double>{
      WeaknessTier.weak: config.weakRatio,
      WeaknessTier.medium: config.mediumRatio,
      WeaknessTier.strong: config.strongRatio,
    };
    final quotas = {
      for (final entry in ratios.entries)
        entry.key: (entry.value * count).floor(),
    };
    var remaining = count - quotas.values.fold(0, (sum, value) => sum + value);
    final remainderOrder = ratios.entries.toList()
      ..sort((a, b) {
        final aRemainder = (a.value * count) - (a.value * count).floor();
        final bRemainder = (b.value * count) - (b.value * count).floor();
        return bRemainder.compareTo(aRemainder);
      });

    for (final entry in remainderOrder) {
      if (remaining == 0) {
        break;
      }
      quotas[entry.key] = quotas[entry.key]! + 1;
      remaining--;
    }
    return quotas;
  }
}
