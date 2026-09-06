class AnswerRecord {
  const AnswerRecord({
    required this.questionId,
    required this.selectedOptionId,
    required this.timeSpent,
    required this.answeredAt,
    this.changedAnswer = false,
  });

  final String questionId;
  final String selectedOptionId;
  final Duration timeSpent;
  final DateTime answeredAt;
  final bool changedAnswer;
}
