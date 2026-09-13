import 'package:exam_coach/analytics/analytics_events.dart';
import 'package:exam_coach/app/app.dart';
import 'package:exam_coach/features/ai_coach/application/ai_coach_context_builder.dart';
import 'package:exam_coach/features/ai_coach/application/ai_coach_cubit.dart';
import 'package:exam_coach/features/ai_coach/domain/ai_coach_cache_store.dart';
import 'package:exam_coach/features/ai_coach/domain/ai_coach_repository.dart';
import 'package:exam_coach/features/auth/application/auth_cubit.dart';
import 'package:exam_coach/features/auth/domain/user_identity.dart';
import 'package:exam_coach/features/exam/data/mock_question_repository.dart';
import 'package:exam_coach/features/learning/application/learning_flow_cubit.dart';
import 'package:exam_coach/features/subscription/application/subscription_cubit.dart';
import 'package:exam_coach/features/subscription/domain/subscription_repository.dart';
import 'package:exam_coach/learning_engine/adaptive_drill_engine.dart';
import 'package:exam_coach/learning_engine/recommendation_engine.dart';
import 'package:exam_coach/learning_engine/scoring_engine.dart';
import 'package:exam_coach/learning_engine/weakness_analyzer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('primary flow remains usable with 200 percent text scaling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final semantics = tester.ensureSemantics();

    final questions = MockQuestionRepository();
    final learning = LearningFlowCubit(
      questionRepository: questions,
      scoringEngine: const ScoringEngine(),
      weaknessAnalyzer: const WeaknessAnalyzer(),
      recommendationEngine: const RecommendationEngine(),
      adaptiveDrillEngine: const AdaptiveDrillEngine(),
    );
    final aiCoach = AiCoachCubit(
      contextBuilder: AiCoachContextBuilder(questions),
      repository: const UnavailableAiCoachRepository('Test mode'),
      cacheStore: MemoryAiCoachCacheStore(),
      userIdentity: UserIdentity(),
      analytics: InMemoryAnalytics(),
    );
    final subscription = SubscriptionCubit(
      repository: const UnavailableSubscriptionRepository('Test mode'),
      userIdentity: UserIdentity(),
      analytics: InMemoryAnalytics(),
    );

    await tester.pumpWidget(
      ExamCoachApp(
        learningFlowCubit: learning,
        authCubit: AuthCubit.unavailable('Test mode'),
        aiCoachCubit: aiCoach,
        subscriptionCubit: subscription,
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('start-tryout-button')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Mulai tryout'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('start-tryout-button'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('start-tryout-button')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('begin-session-button')));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Progres sesi'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('answer-a')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(r'^Pilihan A:')), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
