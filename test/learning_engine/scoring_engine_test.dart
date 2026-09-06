import 'package:exam_coach/features/exam/domain/models/answer_record.dart';
import 'package:exam_coach/learning_engine/scoring_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/question_fixture.dart';

void main() {
  const engine = ScoringEngine();
  final answeredAt = DateTime.utc(2026, 9, 5);

  test('calculates correctness and percentage deterministically', () {
    final questions = [questionFixture(id: 'q1'), questionFixture(id: 'q2')];
    final result = engine.calculate(
      questions: questions,
      answers: [
        AnswerRecord(
          questionId: 'q1',
          selectedOptionId: 'a',
          timeSpent: const Duration(seconds: 20),
          answeredAt: answeredAt,
        ),
        AnswerRecord(
          questionId: 'q2',
          selectedOptionId: 'b',
          timeSpent: const Duration(seconds: 25),
          answeredAt: answeredAt,
        ),
      ],
    );

    expect(result.correct, 1);
    expect(result.total, 2);
    expect(result.accuracy, 0.5);
    expect(result.percentage, 50);
  });

  test('rejects answers for questions outside the scored set', () {
    expect(
      () => engine.calculate(
        questions: [questionFixture(id: 'q1')],
        answers: [
          AnswerRecord(
            questionId: 'missing',
            selectedOptionId: 'a',
            timeSpent: Duration.zero,
            answeredAt: answeredAt,
          ),
        ],
      ),
      throwsArgumentError,
    );
  });
}
