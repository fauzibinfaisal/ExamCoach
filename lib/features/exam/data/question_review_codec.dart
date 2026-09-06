import 'dart:convert';

import 'package:exam_coach/features/exam/domain/models/question_pack.dart';
import 'package:exam_coach/features/exam/domain/models/question_pack_review.dart';

class QuestionReviewValidationException implements Exception {
  const QuestionReviewValidationException(this.issues);

  final List<String> issues;

  @override
  String toString() =>
      'Question review is incomplete:\n- ${issues.join('\n- ')}';
}

class QuestionReviewCodec {
  const QuestionReviewCodec();

  static const schemaVersion = 1;

  QuestionReviewSubmission decode(String source) {
    late final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('Review file is not valid JSON: ${error.message}');
    }
    final root = _asObject(decoded, 'review');
    final version = _asInt(root['schemaVersion'], 'review.schemaVersion');
    if (version != schemaVersion) {
      throw FormatException(
        'review.schemaVersion must be $schemaVersion, received $version.',
      );
    }
    final rawChecks = _asObject(root['checks'], 'review.checks');
    final expectedCheckNames = QuestionReviewCriterion.values
        .map((criterion) => criterion.name)
        .toSet();
    final unexpectedChecks = rawChecks.keys.toSet().difference(
      expectedCheckNames,
    );
    if (unexpectedChecks.isNotEmpty) {
      throw FormatException(
        'review.checks contains unknown criteria: ${unexpectedChecks.join(', ')}.',
      );
    }
    final checks = <QuestionReviewCriterion, bool>{};
    for (final criterion in QuestionReviewCriterion.values) {
      checks[criterion] = _asBool(
        rawChecks[criterion.name],
        'review.checks.${criterion.name}',
      );
    }
    return QuestionReviewSubmission(
      packId: _asString(root['packId'], 'review.packId'),
      contentSha256: _asString(root['contentSha256'], 'review.contentSha256'),
      reviewerId: _asString(root['reviewerId'], 'review.reviewerId'),
      reviewedAt: _asNullableDateTime(root['reviewedAt'], 'review.reviewedAt'),
      decision: _reviewDecision(root['decision'], 'review.decision'),
      notes: _asText(root['notes'], 'review.notes'),
      provenanceDecision: _provenanceDecision(
        root['provenanceDecision'],
        'review.provenanceDecision',
      ),
      provenanceNotes: _asText(
        root['provenanceNotes'],
        'review.provenanceNotes',
      ),
      reviewedQuestionIds:
          _asList(root['reviewedQuestionIds'], 'review.reviewedQuestionIds')
              .indexed
              .map(
                (entry) => _asString(
                  entry.$2,
                  'review.reviewedQuestionIds[${entry.$1}]',
                ),
              )
              .toList(growable: false),
      checks: checks,
    );
  }

  String encode(QuestionReviewSubmission review) {
    const encoder = JsonEncoder.withIndent('  ');
    return '${encoder.convert({
      'schemaVersion': schemaVersion,
      'packId': review.packId,
      'contentSha256': review.contentSha256,
      'reviewerId': review.reviewerId,
      'reviewedAt': review.reviewedAt?.toUtc().toIso8601String(),
      'decision': review.decision.name,
      'notes': review.notes,
      'provenanceDecision': review.provenanceDecision.name,
      'provenanceNotes': review.provenanceNotes,
      'reviewedQuestionIds': review.reviewedQuestionIds,
      'checks': {for (final criterion in QuestionReviewCriterion.values) criterion.name: review.checks[criterion] ?? false},
    })}\n';
  }

  QuestionReviewSubmission template({
    required QuestionPack pack,
    required String reviewerId,
    required String contentSha256,
  }) => QuestionReviewSubmission(
    packId: pack.id,
    contentSha256: contentSha256,
    reviewerId: reviewerId,
    reviewedAt: null,
    decision: QuestionReviewDecision.pending,
    notes: '',
    provenanceDecision: QuestionProvenanceDecision.pending,
    provenanceNotes: '',
    reviewedQuestionIds: [for (final question in pack.questions) question.id],
    checks: {
      for (final criterion in QuestionReviewCriterion.values) criterion: false,
    },
  );

  QuestionPackReviewEvidence approve({
    required QuestionReviewSubmission submission,
    required QuestionPack pack,
    required String contentSha256,
  }) {
    final issues = approvalIssues(
      submission: submission,
      pack: pack,
      contentSha256: contentSha256,
    );
    if (issues.isNotEmpty) {
      throw QuestionReviewValidationException(issues);
    }
    return QuestionPackReviewEvidence(
      contentSha256: submission.contentSha256,
      reviewerId: submission.reviewerId,
      reviewedAt: submission.reviewedAt!,
      notes: submission.notes.trim(),
      provenanceDecision: submission.provenanceDecision,
      provenanceNotes: submission.provenanceNotes.trim(),
      reviewedQuestionIds: submission.reviewedQuestionIds,
      checks: submission.checks,
    );
  }

  List<String> approvalIssues({
    required QuestionReviewSubmission submission,
    required QuestionPack pack,
    required String contentSha256,
  }) {
    final issues = <String>[];
    final idPattern = RegExp(r'^[a-z0-9]+(?:_[a-z0-9]+)*$');
    if (submission.packId != pack.id) {
      issues.add('packId does not match ${pack.id}.');
    }
    if (submission.contentSha256 != contentSha256) {
      issues.add('contentSha256 does not match the current immutable content.');
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(submission.contentSha256)) {
      issues.add('contentSha256 must be a lowercase SHA-256 digest.');
    }
    if (!idPattern.hasMatch(submission.reviewerId) ||
        submission.reviewerId.length > 128) {
      issues.add('reviewerId must be lowercase snake_case.');
    }
    final reviewedAt = submission.reviewedAt;
    if (reviewedAt == null) {
      issues.add('reviewedAt is required after the human review is complete.');
    } else {
      if (!reviewedAt.isUtc) {
        issues.add('reviewedAt must include a UTC timezone.');
      }
      if (reviewedAt.isBefore(pack.generation.generatedAt)) {
        issues.add('reviewedAt cannot be earlier than generatedAt.');
      }
    }
    if (submission.decision != QuestionReviewDecision.approved) {
      issues.add('decision must be approved.');
    }
    if (submission.notes.trim().length < 10) {
      issues.add('notes must contain at least 10 characters.');
    }
    if (submission.provenanceDecision == QuestionProvenanceDecision.pending) {
      issues.add('provenanceDecision must be completed.');
    }
    if (submission.provenanceNotes.trim().length < 10) {
      issues.add('provenanceNotes must contain at least 10 characters.');
    }
    final expectedQuestionIds = pack.questions
        .map((question) => question.id)
        .toSet();
    final reviewedQuestionIds = submission.reviewedQuestionIds.toSet();
    if (reviewedQuestionIds.length != submission.reviewedQuestionIds.length ||
        reviewedQuestionIds.length != expectedQuestionIds.length ||
        !reviewedQuestionIds.containsAll(expectedQuestionIds)) {
      issues.add(
        'reviewedQuestionIds must contain every question exactly once.',
      );
    }
    for (final criterion in QuestionReviewCriterion.values) {
      if (submission.checks[criterion] != true) {
        issues.add('checks.${criterion.name} must be true.');
      }
    }
    return List.unmodifiable(issues);
  }
}

class QuestionReviewEvidenceCodec {
  const QuestionReviewEvidenceCodec();

  QuestionPackReviewEvidence decode(Object? source, String path) {
    final value = _asObject(source, path);
    final rawChecks = _asObject(value['checks'], '$path.checks');
    return QuestionPackReviewEvidence(
      contentSha256: _asString(value['contentSha256'], '$path.contentSha256'),
      reviewerId: _asString(value['reviewerId'], '$path.reviewerId'),
      reviewedAt: _asDateTime(value['reviewedAt'], '$path.reviewedAt'),
      notes: _asString(value['notes'], '$path.notes'),
      provenanceDecision: _provenanceDecision(
        value['provenanceDecision'],
        '$path.provenanceDecision',
      ),
      provenanceNotes: _asString(
        value['provenanceNotes'],
        '$path.provenanceNotes',
      ),
      reviewedQuestionIds:
          _asList(value['reviewedQuestionIds'], '$path.reviewedQuestionIds')
              .indexed
              .map(
                (entry) => _asString(
                  entry.$2,
                  '$path.reviewedQuestionIds[${entry.$1}]',
                ),
              )
              .toList(growable: false),
      checks: {
        for (final criterion in QuestionReviewCriterion.values)
          criterion: _asBool(
            rawChecks[criterion.name],
            '$path.checks.${criterion.name}',
          ),
      },
    );
  }

  Map<String, Object?> encode(QuestionPackReviewEvidence review) => {
    'contentSha256': review.contentSha256,
    'reviewerId': review.reviewerId,
    'reviewedAt': review.reviewedAt.toUtc().toIso8601String(),
    'notes': review.notes,
    'provenanceDecision': review.provenanceDecision.name,
    'provenanceNotes': review.provenanceNotes,
    'reviewedQuestionIds': review.reviewedQuestionIds,
    'checks': {
      for (final criterion in QuestionReviewCriterion.values)
        criterion.name: review.checks[criterion] ?? false,
    },
  };

  QuestionPackPublication decodePublication(Object? source, String path) {
    final value = _asObject(source, path);
    return QuestionPackPublication(
      publisherId: _asString(value['publisherId'], '$path.publisherId'),
      publishedAt: _asDateTime(value['publishedAt'], '$path.publishedAt'),
    );
  }

  Map<String, Object?> encodePublication(QuestionPackPublication publication) =>
      {
        'publisherId': publication.publisherId,
        'publishedAt': publication.publishedAt.toUtc().toIso8601String(),
      };
}

Map<String, Object?> _asObject(Object? value, String path) {
  if (value is! Map) {
    throw FormatException('$path must be a JSON object.');
  }
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<Object?> _asList(Object? value, String path) {
  if (value is! List) {
    throw FormatException('$path must be a JSON array.');
  }
  return value;
}

String _asString(Object? value, String path) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$path must be a non-empty string.');
  }
  return value.trim();
}

String _asText(Object? value, String path) {
  if (value is! String) {
    throw FormatException('$path must be a string.');
  }
  return value;
}

int _asInt(Object? value, String path) {
  if (value is! int) {
    throw FormatException('$path must be an integer.');
  }
  return value;
}

bool _asBool(Object? value, String path) {
  if (value is! bool) {
    throw FormatException('$path must be a boolean.');
  }
  return value;
}

DateTime _asDateTime(Object? value, String path) {
  final source = _asString(value, path);
  final parsed = DateTime.tryParse(source);
  if (parsed == null) {
    throw FormatException('$path must be an ISO-8601 timestamp.');
  }
  return parsed;
}

DateTime? _asNullableDateTime(Object? value, String path) {
  if (value == null) {
    return null;
  }
  return _asDateTime(value, path);
}

QuestionReviewDecision _reviewDecision(Object? value, String path) {
  final name = _asString(value, path);
  try {
    return QuestionReviewDecision.values.byName(name);
  } on ArgumentError {
    throw FormatException('$path must be pending, approved, or rejected.');
  }
}

QuestionProvenanceDecision _provenanceDecision(Object? value, String path) {
  final name = _asString(value, path);
  try {
    return QuestionProvenanceDecision.values.byName(name);
  } on ArgumentError {
    throw FormatException(
      '$path must be pending, original, licensed, publicDomain, or aiGeneratedOriginal.',
    );
  }
}
