import 'package:exam_coach/analytics/analytics_events.dart';
import 'package:exam_coach/features/auth/domain/user_identity.dart';
import 'package:exam_coach/features/exam/data/mock_question_repository.dart';
import 'package:exam_coach/features/exam/domain/models/exam_session.dart';
import 'package:exam_coach/features/learning/application/learning_flow_cubit.dart';
import 'package:exam_coach/features/learning/application/learning_flow_state.dart';
import 'package:exam_coach/learning_engine/adaptive_drill_engine.dart';
import 'package:exam_coach/learning_engine/models/weakness_profile.dart';
import 'package:exam_coach/learning_engine/recommendation_engine.dart';
import 'package:exam_coach/learning_engine/scoring_engine.dart';
import 'package:exam_coach/learning_engine/weakness_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('owns newly created sessions with the bound account identity', () async {
    final identity = UserIdentity(boundUserId: 'firebase_user_123');
    identity.bindAuthenticatedUser('firebase_user_123');
    final cubit = LearningFlowCubit(
      questionRepository: MockQuestionRepository(),
      scoringEngine: const ScoringEngine(),
      weaknessAnalyzer: const WeaknessAnalyzer(),
      recommendationEngine: const RecommendationEngine(),
      adaptiveDrillEngine: const AdaptiveDrillEngine(),
      userIdentity: identity,
    );
    addTearDown(cubit.close);

    expect(await cubit.startTryout(), isTrue);
    expect(cubit.state.session?.userId, 'firebase_user_123');
  });

  test('orchestrates tryout result and recommended drill locally', () async {
    final cubit = LearningFlowCubit(
      questionRepository: MockQuestionRepository(),
      scoringEngine: const ScoringEngine(),
      weaknessAnalyzer: const WeaknessAnalyzer(),
      recommendationEngine: const RecommendationEngine(),
      adaptiveDrillEngine: const AdaptiveDrillEngine(),
    );
    addTearDown(cubit.close);

    await cubit.startTryout();
    expect(cubit.state.status, LearningFlowStatus.answering);
    expect(cubit.state.questions, hasLength(6));

    for (var index = 0; index < 6; index++) {
      cubit.selectOption('a');
      await cubit.submitCurrentAnswer(timeSpent: const Duration(seconds: 30));
    }

    expect(cubit.state.status, LearningFlowStatus.reviewing);
    expect(await cubit.completeCurrentSession(), isTrue);
    expect(cubit.state.status, LearningFlowStatus.result);
    expect(cubit.state.latestScore, isNotNull);
    expect(cubit.state.profiles, hasLength(3));
    expect(cubit.state.recommendation, isNotNull);
    expect(cubit.state.answerHistory, hasLength(6));

    expect(await cubit.startRecommendedDrill(), isTrue);
    expect(cubit.state.status, LearningFlowStatus.answering);
    expect(cubit.state.mode, ExamSessionMode.adaptiveDrill);
    expect(cubit.state.questions, hasLength(6));
    expect(cubit.state.answerHistory, hasLength(6));

    for (var index = 0; index < 6; index++) {
      cubit.selectOption('a');
      await cubit.submitCurrentAnswer(timeSpent: const Duration(seconds: 30));
    }

    expect(cubit.state.status, LearningFlowStatus.reviewing);
    expect(await cubit.completeCurrentSession(), isTrue);
    expect(cubit.state.status, LearningFlowStatus.result);
    expect(cubit.state.answerHistory, hasLength(12));
    expect(cubit.state.previousProfiles, isNotEmpty);
    expect(
      cubit.state.profiles.any(
        (profile) => profile.trend != PerformanceTrend.insufficientData,
      ),
      isTrue,
    );
  });

  test('supports skip and answer changes before scoring', () async {
    final analytics = InMemoryAnalytics();
    final cubit = LearningFlowCubit(
      questionRepository: MockQuestionRepository(),
      scoringEngine: const ScoringEngine(),
      weaknessAnalyzer: const WeaknessAnalyzer(),
      recommendationEngine: const RecommendationEngine(),
      adaptiveDrillEngine: const AdaptiveDrillEngine(),
      analytics: analytics,
    );
    addTearDown(cubit.close);

    await cubit.startTryout();
    await cubit.skipCurrentQuestion(timeSpent: const Duration(seconds: 5));
    for (var index = 1; index < 6; index++) {
      cubit.selectOption('a');
      await cubit.submitCurrentAnswer(timeSpent: const Duration(seconds: 10));
    }

    expect(cubit.state.status, LearningFlowStatus.reviewing);
    expect(cubit.state.answeredCount, 5);
    expect(cubit.state.skippedCount, 1);

    expect(await cubit.goToQuestion(0), isTrue);
    final correctOptionId = cubit.state.currentQuestion!.correctOptionId;
    cubit.selectOption(correctOptionId);
    expect(
      await cubit.submitCurrentAnswer(timeSpent: const Duration(seconds: 7)),
      isTrue,
    );

    expect(cubit.state.status, LearningFlowStatus.reviewing);
    expect(cubit.state.answeredCount, 6);
    expect(cubit.state.skippedCount, 0);
    expect(cubit.state.currentAnswers.first.changedAnswer, isTrue);

    expect(await cubit.completeCurrentSession(), isTrue);
    expect(cubit.state.latestScore?.total, 6);
    expect(cubit.state.answerHistory, hasLength(6));

    await cubit.recordQuestionReviewViewed();
    final names = analytics.events.map((event) => event.name);
    expect(names, contains(AnalyticsEvents.questionSkipped));
    expect(names, contains(AnalyticsEvents.answerChanged));
    expect(names, contains(AnalyticsEvents.questionAnswered));
    expect(names, contains(AnalyticsEvents.practiceCompleted));
    expect(names, contains(AnalyticsEvents.questionReviewViewed));
  });

  test('cancels an active session without adding learning history', () async {
    final analytics = InMemoryAnalytics();
    final cubit = LearningFlowCubit(
      questionRepository: MockQuestionRepository(),
      scoringEngine: const ScoringEngine(),
      weaknessAnalyzer: const WeaknessAnalyzer(),
      recommendationEngine: const RecommendationEngine(),
      adaptiveDrillEngine: const AdaptiveDrillEngine(),
      analytics: analytics,
    );
    addTearDown(cubit.close);

    await cubit.startTryout();
    cubit.selectOption('a');
    await cubit.submitCurrentAnswer(timeSpent: const Duration(seconds: 10));

    expect(await cubit.cancelSession(), isTrue);
    expect(cubit.state.status, LearningFlowStatus.idle);
    expect(cubit.state.hasActiveSession, isFalse);
    expect(cubit.state.answerHistory, isEmpty);
    expect(
      analytics.events.map((event) => event.name),
      contains(AnalyticsEvents.practiceCancelled),
    );
  });

  test('scores an unchanged skipped response as incorrect', () async {
    final cubit = LearningFlowCubit(
      questionRepository: MockQuestionRepository(),
      scoringEngine: const ScoringEngine(),
      weaknessAnalyzer: const WeaknessAnalyzer(),
      recommendationEngine: const RecommendationEngine(),
      adaptiveDrillEngine: const AdaptiveDrillEngine(),
    );
    addTearDown(cubit.close);

    await cubit.startTryout();
    await cubit.skipCurrentQuestion(timeSpent: const Duration(seconds: 2));
    for (var index = 1; index < 6; index++) {
      cubit.selectOption(cubit.state.currentQuestion!.correctOptionId);
      await cubit.submitCurrentAnswer(timeSpent: const Duration(seconds: 8));
    }

    expect(cubit.state.status, LearningFlowStatus.reviewing);
    expect(await cubit.completeCurrentSession(), isTrue);
    expect(cubit.state.latestScore?.total, 6);
    expect(cubit.state.latestScore?.correct, 5);
    expect(cubit.state.latestScore?.evaluations.first.selectedOptionId, isNull);
    expect(cubit.state.latestScore?.evaluations.first.isCorrect, isFalse);
    expect(cubit.state.answerHistory.first.isSkipped, isTrue);
  });
}
