import 'package:exam_coach/features/ai_coach/domain/ai_coach_models.dart';
import 'package:exam_coach/features/exam/domain/models/exam_session.dart';
import 'package:exam_coach/features/exam/domain/repositories/question_repository.dart';
import 'package:exam_coach/features/learning/application/learning_flow_state.dart';

class AiCoachContextBuilder {
  const AiCoachContextBuilder(this._questionRepository);

  final QuestionRepository _questionRepository;

  AiCoachContext? build(LearningFlowState state) {
    final session =
        state.latestCompletedSession ??
        (state.session?.status == ExamSessionStatus.completed
            ? state.session
            : null);
    final score = state.latestScore;
    final recommendation = state.recommendation;
    final endedAt = session?.endedAt;
    if (session == null ||
        score == null ||
        recommendation == null ||
        endedAt == null ||
        state.profiles.isEmpty ||
        session.questionIds.isEmpty) {
      return null;
    }

    final questionsById = {
      for (final question in _questionRepository.allQuestions)
        question.id: question,
    };
    final sourceQuestion = questionsById[session.questionIds.first];
    if (sourceQuestion == null) return null;

    final orderedProfiles = [...state.profiles]
      ..sort((left, right) {
        final byWeakness = right.weaknessScore.compareTo(left.weaknessScore);
        if (byWeakness != 0) return byWeakness;
        return left.taxonomyNodeId.compareTo(right.taxonomyNodeId);
      });

    return AiCoachContext(
      sourceSessionId: session.id,
      examId: sourceQuestion.taxonomy.examId,
      testId: session.testId,
      scorePercentage: score.percentage,
      completedAt: endedAt,
      topWeaknesses: List.unmodifiable(
        orderedProfiles
            .take(3)
            .map(
              (profile) => AiCoachWeaknessContext(
                taxonomyNodeId: profile.taxonomyNodeId.trim(),
                label: profile.taxonomyLabel.trim(),
                weaknessBasisPoints: (profile.weaknessScore * 10000).round(),
                confidenceBasisPoints: (profile.confidence * 10000).round(),
                sampleSize: profile.sampleSize,
                trend: profile.trend.name,
                evidence: List.unmodifiable(
                  profile.evidence.take(3).map((item) => item.trim()),
                ),
              ),
            ),
      ),
      recommendation: AiCoachRecommendationContext(
        type: recommendation.type.name,
        targetTaxonomyId: recommendation.targetTaxonomyId.trim(),
        targetLabel: recommendation.targetLabel.trim(),
        reasonCode: recommendation.reasonCode.name,
        reason: recommendation.reason.trim(),
        expectedBenefit: recommendation.expectedBenefit.trim(),
        estimatedMinutes: recommendation.estimatedEffort.inMinutes,
        confidenceBasisPoints: (recommendation.confidence * 10000).round(),
      ),
    );
  }
}
