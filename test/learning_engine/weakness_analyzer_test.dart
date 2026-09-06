import 'package:exam_coach/features/exam/domain/models/answer_record.dart';
import 'package:exam_coach/learning_engine/models/weakness_profile.dart';
import 'package:exam_coach/learning_engine/weakness_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/question_fixture.dart';

void main() {
  const analyzer = WeaknessAnalyzer();
  final answeredAt = DateTime.utc(2026, 9, 5);

  AnswerRecord answer(String id, String option, {int seconds = 30}) =>
      AnswerRecord(
        questionId: id,
        selectedOptionId: option,
        timeSpent: Duration(seconds: seconds),
        answeredAt: answeredAt,
      );

  test('does not declare a weakness from one answer', () {
    final profiles = analyzer.analyze(
      questions: [questionFixture(id: 'q1')],
      answers: [answer('q1', 'b')],
    );

    expect(profiles.single.sampleSize, 1);
    expect(profiles.single.tier, WeaknessTier.medium);
    expect(profiles.single.confidence, 0.2);
  });

  test('identifies repeated incorrect answers with evidence', () {
    final profiles = analyzer.analyze(
      questions: [
        questionFixture(id: 'q1'),
        questionFixture(id: 'q2'),
      ],
      answers: [answer('q1', 'b'), answer('q2', 'b')],
    );

    expect(profiles.single.tier, WeaknessTier.weak);
    expect(profiles.single.weaknessScore, closeTo(0.8, 0.001));
    expect(profiles.single.evidence.first, '0 dari 2 jawaban benar');
  });

  test('reports improvement against a previous profile', () {
    const previous = WeaknessProfile(
      taxonomyNodeId: 'topic_ratio',
      taxonomyLabel: 'Ratio',
      weaknessScore: 0.8,
      confidence: 0.4,
      sampleSize: 2,
      trend: PerformanceTrend.insufficientData,
      tier: WeaknessTier.weak,
      evidence: [],
    );
    final questions = [
      questionFixture(id: 'q1'),
      questionFixture(id: 'q2'),
      questionFixture(id: 'q3'),
      questionFixture(id: 'q4'),
    ];
    final profiles = analyzer.analyze(
      questions: questions,
      answers: [
        answer('q1', 'b'),
        answer('q2', 'b'),
        answer('q3', 'a'),
        answer('q4', 'a'),
      ],
      previousProfiles: const [previous],
    );

    expect(profiles.single.weaknessScore, lessThan(previous.weaknessScore));
    expect(profiles.single.trend, PerformanceTrend.improving);
  });
}
