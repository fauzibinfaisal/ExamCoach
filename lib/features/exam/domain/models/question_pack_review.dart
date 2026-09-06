enum QuestionReviewDecision { pending, approved, rejected }

enum QuestionProvenanceDecision {
  pending,
  original,
  licensed,
  publicDomain,
  aiGeneratedOriginal,
}

enum QuestionReviewCriterion {
  factualCorrectness,
  singleDefensibleAnswer,
  promptClarity,
  distractorQuality,
  explanationQuality,
  taxonomyAccuracy,
  difficultyCalibration,
  languageQuality,
  inclusivity,
  provenanceRights,
  similarityRisk,
}

class QuestionReviewSubmission {
  QuestionReviewSubmission({
    required this.packId,
    required this.contentSha256,
    required this.reviewerId,
    required this.reviewedAt,
    required this.decision,
    required this.notes,
    required this.provenanceDecision,
    required this.provenanceNotes,
    required List<String> reviewedQuestionIds,
    required Map<QuestionReviewCriterion, bool> checks,
  }) : reviewedQuestionIds = List.unmodifiable(reviewedQuestionIds),
       checks = Map.unmodifiable(checks);

  final String packId;
  final String contentSha256;
  final String reviewerId;
  final DateTime? reviewedAt;
  final QuestionReviewDecision decision;
  final String notes;
  final QuestionProvenanceDecision provenanceDecision;
  final String provenanceNotes;
  final List<String> reviewedQuestionIds;
  final Map<QuestionReviewCriterion, bool> checks;
}

class QuestionPackReviewEvidence {
  QuestionPackReviewEvidence({
    required this.contentSha256,
    required this.reviewerId,
    required this.reviewedAt,
    required this.notes,
    required this.provenanceDecision,
    required this.provenanceNotes,
    required List<String> reviewedQuestionIds,
    required Map<QuestionReviewCriterion, bool> checks,
  }) : reviewedQuestionIds = List.unmodifiable(reviewedQuestionIds),
       checks = Map.unmodifiable(checks);

  final String contentSha256;
  final String reviewerId;
  final DateTime reviewedAt;
  final String notes;
  final QuestionProvenanceDecision provenanceDecision;
  final String provenanceNotes;
  final List<String> reviewedQuestionIds;
  final Map<QuestionReviewCriterion, bool> checks;
}

class QuestionPackPublication {
  const QuestionPackPublication({
    required this.publisherId,
    required this.publishedAt,
  });

  final String publisherId;
  final DateTime publishedAt;
}
