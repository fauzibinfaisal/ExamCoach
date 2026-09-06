class AnswerEvaluation {
  const AnswerEvaluation({
    required this.questionId,
    required this.selectedOptionId,
    required this.correctOptionId,
    required this.isCorrect,
  });

  final String questionId;
  final String selectedOptionId;
  final String correctOptionId;
  final bool isCorrect;
}

class ScoreResult {
  const ScoreResult({required this.evaluations});

  final List<AnswerEvaluation> evaluations;

  int get total => evaluations.length;

  int get correct => evaluations.where((item) => item.isCorrect).length;

  double get accuracy => total == 0 ? 0 : correct / total;

  int get percentage => (accuracy * 100).round();
}
