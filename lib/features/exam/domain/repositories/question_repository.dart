import 'package:exam_coach/features/exam/domain/models/question.dart';

abstract interface class QuestionRepository {
  List<Question> get allQuestions;

  List<Question> get initialTryoutQuestions;
}
