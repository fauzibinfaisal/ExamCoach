import 'package:exam_coach/features/exam/domain/models/question.dart';

abstract interface class QuestionReviewAccessPolicy {
  bool canViewExplanation(Question question);
}

class DevelopmentQuestionReviewAccessPolicy
    implements QuestionReviewAccessPolicy {
  const DevelopmentQuestionReviewAccessPolicy();

  @override
  bool canViewExplanation(Question question) => true;
}
