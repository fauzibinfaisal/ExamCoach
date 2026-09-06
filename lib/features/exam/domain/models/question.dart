import 'package:exam_coach/features/exam/domain/models/taxonomy_path.dart';

enum QuestionDifficulty { easy, medium, hard }

enum QuestionValidationStatus { draft, validated, published, retired }

class QuestionOption {
  const QuestionOption({required this.id, required this.text});

  final String id;
  final String text;
}

class Question {
  const Question({
    required this.id,
    required this.prompt,
    required this.options,
    required this.correctOptionId,
    required this.taxonomy,
    required this.difficulty,
    required this.cognitiveType,
    required this.estimatedTime,
    required this.trapType,
    required this.provenance,
    required this.author,
    required this.reviewer,
    required this.explanation,
    required this.validationStatus,
    required this.version,
  });

  final String id;
  final String prompt;
  final List<QuestionOption> options;
  final String correctOptionId;
  final TaxonomyPath taxonomy;
  final QuestionDifficulty difficulty;
  final String cognitiveType;
  final Duration estimatedTime;
  final String trapType;
  final String provenance;
  final String author;
  final String? reviewer;
  final String explanation;
  final QuestionValidationStatus validationStatus;
  final int version;
}
