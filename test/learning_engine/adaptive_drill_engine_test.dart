import 'package:exam_coach/learning_engine/adaptive_drill_engine.dart';
import 'package:exam_coach/learning_engine/models/weakness_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/question_fixture.dart';

void main() {
  const engine = AdaptiveDrillEngine();

  WeaknessProfile profile(String topic, WeaknessTier tier) => WeaknessProfile(
    taxonomyNodeId: topic,
    taxonomyLabel: topic,
    weaknessScore: switch (tier) {
      WeaknessTier.weak => 0.8,
      WeaknessTier.medium => 0.4,
      WeaknessTier.strong => 0.1,
    },
    confidence: 1,
    sampleSize: 5,
    trend: PerformanceTrend.stable,
    tier: tier,
    evidence: const [],
  );

  test('selects a deterministic 70/20/10 composition for ten questions', () {
    final questions = [
      for (var i = 0; i < 10; i++)
        questionFixture(id: 'weak_$i', topicId: 'weak'),
      for (var i = 0; i < 10; i++)
        questionFixture(id: 'medium_$i', topicId: 'medium'),
      for (var i = 0; i < 10; i++)
        questionFixture(id: 'strong_$i', topicId: 'strong'),
    ];
    final selected = engine.select(
      questions: questions,
      profiles: [
        profile('weak', WeaknessTier.weak),
        profile('medium', WeaknessTier.medium),
        profile('strong', WeaknessTier.strong),
      ],
      previouslyAttemptedQuestionIds: const {'weak_0'},
      count: 10,
    );

    expect(selected.where((q) => q.taxonomy.topicId == 'weak'), hasLength(7));
    expect(selected.where((q) => q.taxonomy.topicId == 'medium'), hasLength(2));
    expect(selected.where((q) => q.taxonomy.topicId == 'strong'), hasLength(1));
    expect(selected.map((q) => q.id), isNot(contains('weak_0')));
  });

  test('fills the drill when a requested tier has too few questions', () {
    final questions = [
      questionFixture(id: 'weak_1', topicId: 'weak'),
      for (var i = 0; i < 5; i++)
        questionFixture(id: 'medium_$i', topicId: 'medium'),
    ];
    final selected = engine.select(
      questions: questions,
      profiles: [
        profile('weak', WeaknessTier.weak),
        profile('medium', WeaknessTier.medium),
      ],
      previouslyAttemptedQuestionIds: const {},
      count: 6,
    );

    expect(selected, hasLength(6));
    expect(selected.map((q) => q.id).toSet(), hasLength(6));
  });
}
