class AnswerRecord {
  const AnswerRecord({
    required this.questionId,
    this.selectedOptionId,
    required this.timeSpent,
    required this.answeredAt,
    this.changedAnswer = false,
  });

  final String questionId;
  final String? selectedOptionId;
  final Duration timeSpent;
  final DateTime answeredAt;
  final bool changedAnswer;

  bool get isSkipped => selectedOptionId == null;
}
