import 'dart:math' as math;

import 'package:exam_coach/features/exam/domain/models/answer_record.dart';
import 'package:exam_coach/features/exam/domain/models/question.dart';
import 'package:exam_coach/learning_engine/models/weakness_profile.dart';

class WeaknessAnalyzerConfig {
  const WeaknessAnalyzerConfig({
    this.algorithmVersion = 'weakness_v1',
    this.accuracyWeight = 0.65,
    this.speedWeight = 0.20,
    this.difficultyWeight = 0.15,
    this.minimumEvidenceForWeakness = 2,
    this.samplesForFullConfidence = 5,
    this.weakThreshold = 0.55,
    this.strongThreshold = 0.30,
    this.trendThreshold = 0.05,
  }) : assert(
         accuracyWeight + speedWeight + difficultyWeight > 0.999 &&
             accuracyWeight + speedWeight + difficultyWeight < 1.001,
       );

  final String algorithmVersion;
  final double accuracyWeight;
  final double speedWeight;
  final double difficultyWeight;
  final int minimumEvidenceForWeakness;
  final int samplesForFullConfidence;
  final double weakThreshold;
  final double strongThreshold;
  final double trendThreshold;
}

class WeaknessAnalyzer {
  const WeaknessAnalyzer({this.config = const WeaknessAnalyzerConfig()});

  final WeaknessAnalyzerConfig config;

  List<WeaknessProfile> analyze({
    required List<Question> questions,
    required List<AnswerRecord> answers,
    List<WeaknessProfile> previousProfiles = const [],
  }) {
    final questionsById = {
      for (final question in questions) question.id: question,
    };
    final groupedAnswers = <String, List<AnswerRecord>>{};

    for (final answer in answers) {
      final question = questionsById[answer.questionId];
      if (question == null) {
        continue;
      }
      groupedAnswers
          .putIfAbsent(question.taxonomy.topicId, () => [])
          .add(answer);
    }

    final previousById = {
      for (final profile in previousProfiles) profile.taxonomyNodeId: profile,
    };
    final profiles = <WeaknessProfile>[];

    for (final entry in groupedAnswers.entries) {
      final topicAnswers = entry.value;
      final topicQuestions = topicAnswers
          .map((answer) => questionsById[answer.questionId]!)
          .toList(growable: false);
      final sampleSize = topicAnswers.length;
      final correctCount = Iterable<int>.generate(sampleSize)
          .where(
            (index) =>
                topicAnswers[index].selectedOptionId ==
                topicQuestions[index].correctOptionId,
          )
          .length;
      final accuracy = correctCount / sampleSize;

      final speedPenalty =
          Iterable<int>.generate(sampleSize).fold<double>(0, (total, index) {
            final expected = topicQuestions[index].estimatedTime.inMilliseconds;
            final actual = topicAnswers[index].timeSpent.inMilliseconds;
            if (expected <= 0 || actual <= expected) {
              return total;
            }
            return total + math.min(1, (actual - expected) / expected);
          }) /
          sampleSize;

      var difficultyTotal = 0.0;
      var difficultyMissed = 0.0;
      for (var index = 0; index < sampleSize; index++) {
        final question = topicQuestions[index];
        final weight = switch (question.difficulty) {
          QuestionDifficulty.easy => 1.0,
          QuestionDifficulty.medium => 1.25,
          QuestionDifficulty.hard => 1.5,
        };
        difficultyTotal += weight;
        if (topicAnswers[index].selectedOptionId != question.correctOptionId) {
          difficultyMissed += weight;
        }
      }
      final difficultyPenalty = difficultyMissed / difficultyTotal;

      final weaknessScore =
          ((1 - accuracy) * config.accuracyWeight) +
          (speedPenalty * config.speedWeight) +
          (difficultyPenalty * config.difficultyWeight);
      final confidence = math
          .min(1, sampleSize / config.samplesForFullConfidence)
          .toDouble();
      final tier = _tierFor(score: weaknessScore, sampleSize: sampleSize);
      final previous = previousById[entry.key];

      profiles.add(
        WeaknessProfile(
          taxonomyNodeId: entry.key,
          taxonomyLabel: topicQuestions.first.taxonomy.topicLabel,
          weaknessScore: weaknessScore,
          confidence: confidence,
          sampleSize: sampleSize,
          trend: _trendFor(weaknessScore, previous),
          tier: tier,
          evidence: [
            '$correctCount dari $sampleSize jawaban benar',
            if (speedPenalty > 0.20) 'Waktu pengerjaan melebihi target',
            if (sampleSize < config.samplesForFullConfidence)
              'Butuh lebih banyak jawaban untuk meningkatkan keyakinan',
          ],
          algorithmVersion: config.algorithmVersion,
        ),
      );
    }

    profiles.sort((a, b) => b.weaknessScore.compareTo(a.weaknessScore));
    return List.unmodifiable(profiles);
  }

  WeaknessTier _tierFor({required double score, required int sampleSize}) {
    if (sampleSize < config.minimumEvidenceForWeakness) {
      return WeaknessTier.medium;
    }
    if (score >= config.weakThreshold) {
      return WeaknessTier.weak;
    }
    if (score < config.strongThreshold) {
      return WeaknessTier.strong;
    }
    return WeaknessTier.medium;
  }

  PerformanceTrend _trendFor(double currentScore, WeaknessProfile? previous) {
    if (previous == null) {
      return PerformanceTrend.insufficientData;
    }
    final difference = currentScore - previous.weaknessScore;
    if (difference <= -config.trendThreshold) {
      return PerformanceTrend.improving;
    }
    if (difference >= config.trendThreshold) {
      return PerformanceTrend.declining;
    }
    return PerformanceTrend.stable;
  }
}
