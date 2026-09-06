import 'dart:convert';
import 'dart:io';

import 'package:exam_coach/features/exam/data/question_pack_codec.dart';
import 'package:exam_coach/features/exam/data/question_pack_fingerprint.dart';
import 'package:exam_coach/features/exam/data/question_pack_promotion_service.dart';
import 'package:exam_coach/features/exam/data/question_review_codec.dart';
import 'package:exam_coach/features/exam/data/question_similarity_analyzer.dart';
import 'package:exam_coach/features/exam/domain/models/question.dart';
import 'package:exam_coach/features/exam/domain/models/question_pack.dart';
import 'package:exam_coach/features/exam/domain/models/question_pack_review.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late QuestionPack draft;

  setUpAll(() {
    draft = const QuestionPackCodec().decode(
      File('content/examples/question_pack.example.json').readAsStringSync(),
    );
  });

  test('incomplete human review cannot approve a draft', () {
    final digest = const QuestionPackFingerprint().compute(draft);
    final template = const QuestionReviewCodec().template(
      pack: draft,
      reviewerId: 'reviewer_fauzi',
      contentSha256: digest,
    );

    expect(
      () => const QuestionReviewCodec().approve(
        submission: template,
        pack: draft,
        contentSha256: digest,
      ),
      throwsA(
        isA<QuestionReviewValidationException>().having(
          (error) => error.issues.join(' '),
          'issues',
          allOf(
            contains('reviewedAt is required'),
            contains('decision must be approved'),
            contains('factualCorrectness'),
          ),
        ),
      ),
    );
  });

  test('validated and published artifacts preserve immutable content', () {
    final review = _approvedReview(draft);
    final validated = const QuestionPackPromotionService().validateDraft(
      draft,
      review,
    );
    final validatedSource = const QuestionPackCodec().encode(validated);
    final decodedValidated = const QuestionPackCodec().decode(validatedSource);
    final published = const QuestionPackPromotionService().publishValidated(
      decodedValidated,
      publisherId: 'publisher_fauzi',
      publishedAt: DateTime.utc(2026, 9, 8),
    );
    final decodedPublished = const QuestionPackCodec().decode(
      const QuestionPackCodec().encode(published),
    );

    const fingerprint = QuestionPackFingerprint();
    expect(validated.validationStatus, QuestionValidationStatus.validated);
    expect(
      decodedPublished.validationStatus,
      QuestionValidationStatus.published,
    );
    expect(decodedPublished.reviewer, 'reviewer_fauzi');
    expect(decodedPublished.publication?.publisherId, 'publisher_fauzi');
    expect(fingerprint.compute(validated), fingerprint.compute(draft));
    expect(fingerprint.compute(decodedPublished), fingerprint.compute(draft));
    expect(
      decodedPublished.questions.map((question) => question.id),
      draft.questions.map((question) => question.id),
    );
  });

  test('review evidence is bound to the exact content digest', () {
    final validated = const QuestionPackPromotionService().validateDraft(
      draft,
      _approvedReview(draft),
    );
    final json =
        jsonDecode(const QuestionPackCodec().encode(validated))
            as Map<String, dynamic>;
    final questions = json['questions'] as List<dynamic>;
    final first = questions.first as Map<String, dynamic>;
    first['prompt'] = '${first['prompt']} Diubah setelah review.';

    expect(
      () => const QuestionPackCodec().decode(jsonEncode(json)),
      throwsA(
        isA<QuestionPackValidationException>().having(
          (error) => error.issues.join(' '),
          'issues',
          contains('does not match immutable pack content'),
        ),
      ),
    );
  });

  test('similarity gate catches normalized matches within and across packs', () {
    final externalDuplicate = _copyWithPrompts(
      draft,
      id: 'pack_cpns_tiu_similarity_v2',
      prompts: [
        '${draft.questions.first.prompt.toUpperCase()}!!!',
        for (final question in draft.questions.skip(1))
          'Konten unik ${question.id} yang tidak serupa dengan soal pembanding lain.',
      ],
    );
    final report = const QuestionSimilarityAnalyzer().analyze(
      target: externalDuplicate,
      existingPacks: [draft],
    );

    expect(report.hasBlockingMatches, isTrue);
    expect(
      report.matches,
      contains(
        isA<QuestionSimilarityMatch>()
            .having(
              (match) => match.questionId,
              'questionId',
              externalDuplicate.questions.first.id,
            )
            .having(
              (match) => match.comparedQuestionId,
              'comparedQuestionId',
              draft.questions.first.id,
            )
            .having((match) => match.exactNormalizedMatch, 'exact', isTrue),
      ),
    );

    final internalDuplicate = _copyWithPrompts(
      draft,
      id: 'pack_cpns_tiu_internal_v2',
      prompts: [
        draft.questions.first.prompt,
        draft.questions.first.prompt,
        for (final question in draft.questions.skip(2)) question.prompt,
      ],
    );
    final internalReport = const QuestionSimilarityAnalyzer().analyze(
      target: internalDuplicate,
      existingPacks: const [],
    );
    expect(internalReport.hasBlockingMatches, isTrue);
    expect(
      internalReport.matches.any(
        (match) => match.comparedPackId == internalDuplicate.id,
      ),
      isTrue,
    );
  });
}

QuestionPackReviewEvidence _approvedReview(QuestionPack pack) {
  final digest = const QuestionPackFingerprint().compute(pack);
  final submission = QuestionReviewSubmission(
    packId: pack.id,
    contentSha256: digest,
    reviewerId: 'reviewer_fauzi',
    reviewedAt: DateTime.utc(2026, 9, 7),
    decision: QuestionReviewDecision.approved,
    notes: 'Seluruh soal diperiksa satu per satu dan layak divalidasi.',
    provenanceDecision: QuestionProvenanceDecision.aiGeneratedOriginal,
    provenanceNotes:
        'Draft AI diperiksa sebagai materi orisinal tanpa salinan.',
    reviewedQuestionIds: [for (final question in pack.questions) question.id],
    checks: {
      for (final criterion in QuestionReviewCriterion.values) criterion: true,
    },
  );
  return const QuestionReviewCodec().approve(
    submission: submission,
    pack: pack,
    contentSha256: digest,
  );
}

QuestionPack _copyWithPrompts(
  QuestionPack source, {
  required String id,
  required List<String> prompts,
}) {
  final questions = <Question>[];
  for (var index = 0; index < source.questions.length; index++) {
    final original = source.questions[index];
    questions.add(
      Question(
        id: '${id}_q_${index + 1}',
        prompt: prompts[index],
        options: original.options,
        correctOptionId: original.correctOptionId,
        taxonomy: original.taxonomy,
        difficulty: original.difficulty,
        cognitiveType: original.cognitiveType,
        estimatedTime: original.estimatedTime,
        trapType: original.trapType,
        provenance: original.provenance,
        author: original.author,
        reviewer: null,
        explanation: original.explanation,
        validationStatus: QuestionValidationStatus.draft,
        version: 2,
      ),
    );
  }
  return QuestionPack(
    id: id,
    title: source.title,
    examId: source.examId,
    testId: source.testId,
    version: 2,
    validationStatus: QuestionValidationStatus.draft,
    author: source.author,
    reviewer: null,
    generation: source.generation,
    tryoutQuestionIds: [for (final question in questions) question.id],
    questions: questions,
  );
}
