import 'package:exam_coach/features/exam/data/question_pack_codec.dart';
import 'package:exam_coach/features/exam/data/question_pack_fingerprint.dart';
import 'package:exam_coach/features/exam/domain/models/question.dart';
import 'package:exam_coach/features/exam/domain/models/question_pack.dart';
import 'package:exam_coach/features/exam/domain/models/question_pack_review.dart';

class QuestionPackPromotionException implements Exception {
  const QuestionPackPromotionException(this.message);

  final String message;

  @override
  String toString() => 'Question pack promotion failed: $message';
}

class QuestionPackPromotionService {
  const QuestionPackPromotionService();

  QuestionPack validateDraft(
    QuestionPack source,
    QuestionPackReviewEvidence review,
  ) {
    if (source.validationStatus != QuestionValidationStatus.draft) {
      throw const QuestionPackPromotionException(
        'Only a draft pack can be promoted to validated.',
      );
    }
    final promoted = _copyWithLifecycle(
      source,
      status: QuestionValidationStatus.validated,
      reviewer: review.reviewerId,
      review: review,
      publication: null,
    );
    _ensureValidAndImmutable(source, promoted);
    return promoted;
  }

  QuestionPack publishValidated(
    QuestionPack source, {
    required String publisherId,
    required DateTime publishedAt,
  }) {
    if (source.validationStatus != QuestionValidationStatus.validated ||
        source.review == null) {
      throw const QuestionPackPromotionException(
        'Only a human-validated pack can be published.',
      );
    }
    final promoted = _copyWithLifecycle(
      source,
      status: QuestionValidationStatus.published,
      reviewer: source.review!.reviewerId,
      review: source.review,
      publication: QuestionPackPublication(
        publisherId: publisherId,
        publishedAt: publishedAt,
      ),
    );
    _ensureValidAndImmutable(source, promoted);
    return promoted;
  }

  void _ensureValidAndImmutable(QuestionPack source, QuestionPack promoted) {
    const fingerprint = QuestionPackFingerprint();
    if (fingerprint.compute(source) != fingerprint.compute(promoted)) {
      throw const QuestionPackPromotionException(
        'Promotion changed immutable content or IDs.',
      );
    }
    final issues = const QuestionPackCodec().validate(promoted);
    if (issues.isNotEmpty) {
      throw QuestionPackPromotionException(issues.join(' '));
    }
  }

  QuestionPack _copyWithLifecycle(
    QuestionPack source, {
    required QuestionValidationStatus status,
    required String reviewer,
    required QuestionPackReviewEvidence? review,
    required QuestionPackPublication? publication,
  }) => QuestionPack(
    id: source.id,
    title: source.title,
    examId: source.examId,
    testId: source.testId,
    version: source.version,
    validationStatus: status,
    author: source.author,
    reviewer: reviewer,
    generation: source.generation,
    tryoutQuestionIds: source.tryoutQuestionIds,
    questions: [
      for (final question in source.questions)
        Question(
          id: question.id,
          prompt: question.prompt,
          options: question.options,
          correctOptionId: question.correctOptionId,
          taxonomy: question.taxonomy,
          difficulty: question.difficulty,
          cognitiveType: question.cognitiveType,
          estimatedTime: question.estimatedTime,
          trapType: question.trapType,
          provenance: question.provenance,
          author: question.author,
          reviewer: reviewer,
          explanation: question.explanation,
          validationStatus: status,
          version: question.version,
        ),
    ],
    review: review,
    publication: publication,
  );
}
