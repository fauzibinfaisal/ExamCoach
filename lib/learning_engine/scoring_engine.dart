import 'package:exam_coach/features/exam/domain/models/answer_record.dart';
import 'package:exam_coach/features/exam/domain/models/question.dart';
import 'package:exam_coach/learning_engine/models/score_result.dart';

class ScoringEngine {
  const ScoringEngine();

  ScoreResult calculate({
    required List<Question> questions,
    required List<AnswerRecord> answers,
  }) {
    final questionsById = {
      for (final question in questions) question.id: question,
    };

    final evaluations = answers
        .map((answer) {
          final question = questionsById[answer.questionId];
          if (question == null) {
            throw ArgumentError('Unknown question: ${answer.questionId}');
          }

          return AnswerEvaluation(
            questionId: question.id,
            selectedOptionId: answer.selectedOptionId,
            correctOptionId: question.correctOptionId,
            isCorrect: answer.selectedOptionId == question.correctOptionId,
          );
        })
        .toList(growable: false);

    return ScoreResult(evaluations: evaluations);
  }
}
