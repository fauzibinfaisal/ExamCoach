import 'package:exam_coach/features/exam/domain/models/question.dart';
import 'package:exam_coach/features/exam/domain/models/question_pack_review.dart';

class QuestionPackGeneration {
  const QuestionPackGeneration({
    required this.provider,
    required this.model,
    required this.promptVersion,
    required this.generatedAt,
  });

  final String provider;
  final String model;
  final String promptVersion;
  final DateTime generatedAt;
}

class QuestionPack {
  const QuestionPack({
    required this.id,
    required this.title,
    required this.examId,
    required this.testId,
    required this.version,
    required this.validationStatus,
    required this.author,
    required this.reviewer,
    required this.generation,
    required this.tryoutQuestionIds,
    required this.questions,
    this.review,
    this.publication,
  });

  final String id;
  final String title;
  final String examId;
  final String testId;
  final int version;
  final QuestionValidationStatus validationStatus;
  final String author;
  final String? reviewer;
  final QuestionPackGeneration generation;
  final List<String> tryoutQuestionIds;
  final List<Question> questions;
  final QuestionPackReviewEvidence? review;
  final QuestionPackPublication? publication;
}
