import 'package:exam_coach/features/exam/domain/models/question.dart';
import 'package:exam_coach/features/exam/domain/models/question_pack.dart';

class QuestionSimilarityMatch {
  const QuestionSimilarityMatch({
    required this.questionId,
    required this.comparedPackId,
    required this.comparedQuestionId,
    required this.score,
    required this.exactNormalizedMatch,
  });

  final String questionId;
  final String comparedPackId;
  final String comparedQuestionId;
  final double score;
  final bool exactNormalizedMatch;
}

class QuestionSimilarityReport {
  QuestionSimilarityReport({
    required this.threshold,
    required List<QuestionSimilarityMatch> matches,
  }) : matches = List.unmodifiable(matches);

  final double threshold;
  final List<QuestionSimilarityMatch> matches;

  bool get hasBlockingMatches => matches.isNotEmpty;
}

class QuestionSimilarityAnalyzer {
  const QuestionSimilarityAnalyzer({this.threshold = 0.82})
    : assert(threshold > 0 && threshold <= 1);

  final double threshold;

  QuestionSimilarityReport analyze({
    required QuestionPack target,
    required Iterable<QuestionPack> existingPacks,
  }) {
    final matches = <QuestionSimilarityMatch>[];
    for (var leftIndex = 0; leftIndex < target.questions.length; leftIndex++) {
      final left = target.questions[leftIndex];
      for (
        var rightIndex = leftIndex + 1;
        rightIndex < target.questions.length;
        rightIndex++
      ) {
        _compare(
          left,
          target.questions[rightIndex],
          comparedPackId: target.id,
          matches: matches,
        );
      }
      for (final pack in existingPacks) {
        if (pack.id == target.id) {
          continue;
        }
        for (final existing in pack.questions) {
          _compare(left, existing, comparedPackId: pack.id, matches: matches);
        }
      }
    }
    matches.sort((left, right) {
      final scoreOrder = right.score.compareTo(left.score);
      if (scoreOrder != 0) {
        return scoreOrder;
      }
      final questionOrder = left.questionId.compareTo(right.questionId);
      if (questionOrder != 0) {
        return questionOrder;
      }
      return left.comparedQuestionId.compareTo(right.comparedQuestionId);
    });
    return QuestionSimilarityReport(threshold: threshold, matches: matches);
  }

  void _compare(
    Question left,
    Question right, {
    required String comparedPackId,
    required List<QuestionSimilarityMatch> matches,
  }) {
    final leftNormalized = _normalize(left.prompt);
    final rightNormalized = _normalize(right.prompt);
    final exact = leftNormalized == rightNormalized;
    final score = exact
        ? 1.0
        : _jaccard(_shingles(leftNormalized), _shingles(rightNormalized));
    if (exact || score >= threshold) {
      matches.add(
        QuestionSimilarityMatch(
          questionId: left.id,
          comparedPackId: comparedPackId,
          comparedQuestionId: right.id,
          score: score,
          exactNormalizedMatch: exact,
        ),
      );
    }
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  static Set<String> _shingles(String normalized) {
    final tokens = normalized.isEmpty ? <String>[] : normalized.split(' ');
    if (tokens.length < 3) {
      return tokens.toSet();
    }
    return {
      for (var index = 0; index <= tokens.length - 3; index++)
        '${tokens[index]} ${tokens[index + 1]} ${tokens[index + 2]}',
    };
  }

  static double _jaccard(Set<String> left, Set<String> right) {
    if (left.isEmpty && right.isEmpty) {
      return 1;
    }
    final union = left.union(right).length;
    if (union == 0) {
      return 0;
    }
    return left.intersection(right).length / union;
  }
}
