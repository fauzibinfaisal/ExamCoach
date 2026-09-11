import 'package:exam_coach/app/app.dart';
import 'package:exam_coach/analytics/analytics_events.dart';
import 'package:exam_coach/features/ai_coach/application/ai_coach_context_builder.dart';
import 'package:exam_coach/features/ai_coach/application/ai_coach_cubit.dart';
import 'package:exam_coach/features/ai_coach/domain/ai_coach_cache_store.dart';
import 'package:exam_coach/features/ai_coach/domain/ai_coach_repository.dart';
import 'package:exam_coach/features/auth/application/auth_cubit.dart';
import 'package:exam_coach/features/auth/domain/user_identity.dart';
import 'package:exam_coach/features/exam/data/mock_question_repository.dart';
import 'package:exam_coach/features/learning/application/learning_flow_cubit.dart';
import 'package:exam_coach/learning_engine/adaptive_drill_engine.dart';
import 'package:exam_coach/learning_engine/recommendation_engine.dart';
import 'package:exam_coach/learning_engine/scoring_engine.dart';
import 'package:exam_coach/learning_engine/weakness_analyzer.dart';
import 'package:exam_coach/features/subscription/application/subscription_cubit.dart';
import 'package:exam_coach/features/subscription/domain/subscription_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens account recovery while Firebase is safely disabled', (
    tester,
  ) async {
    final questions = MockQuestionRepository();
    final cubit = LearningFlowCubit(
      questionRepository: questions,
      scoringEngine: const ScoringEngine(),
      weaknessAnalyzer: const WeaknessAnalyzer(),
      recommendationEngine: const RecommendationEngine(),
      adaptiveDrillEngine: const AdaptiveDrillEngine(),
    );
    await tester.pumpWidget(
      ExamCoachApp(
        learningFlowCubit: cubit,
        authCubit: AuthCubit.unavailable('Test mode'),
        aiCoachCubit: _testAiCoachCubit(questions),
        subscriptionCubit: _testSubscriptionCubit(),
      ),
    );

    expect(find.text('Mode lokal'), findsOneWidget);
    await tester.tap(find.byKey(const Key('account-button')));
    await tester.pumpAndSettle();

    expect(find.text('Akun & sinkronisasi'), findsOneWidget);
    expect(find.text('Firebase belum aktif'), findsOneWidget);
    expect(find.text('Test mode'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('subscription-card')));
    await tester.pumpAndSettle();
    expect(find.text('Paket ExamCoach'), findsOneWidget);
    expect(find.text('Subscriptions disabled for tests'), findsOneWidget);
  });

  testWidgets('requires confirmation before cancelling a new tryout', (
    tester,
  ) async {
    final questions = MockQuestionRepository();
    final cubit = LearningFlowCubit(
      questionRepository: questions,
      scoringEngine: const ScoringEngine(),
      weaknessAnalyzer: const WeaknessAnalyzer(),
      recommendationEngine: const RecommendationEngine(),
      adaptiveDrillEngine: const AdaptiveDrillEngine(),
    );
    await tester.pumpWidget(
      ExamCoachApp(
        learningFlowCubit: cubit,
        authCubit: AuthCubit.unavailable('Test mode'),
        aiCoachCubit: _testAiCoachCubit(questions),
        subscriptionCubit: _testSubscriptionCubit(),
      ),
    );

    await _tapStartTryout(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Batalkan tryout'));
    await tester.pumpAndSettle();

    expect(find.text('Batalkan sesi?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-cancel-session-button')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('start-tryout-button')),
      300,
    );
    expect(find.byKey(const Key('start-tryout-button')), findsOneWidget);
    expect(cubit.state.hasActiveSession, isFalse);
  });

  testWidgets('completes tryout, drill, and updated insight', (tester) async {
    final questions = MockQuestionRepository();
    final cubit = LearningFlowCubit(
      questionRepository: questions,
      scoringEngine: const ScoringEngine(),
      weaknessAnalyzer: const WeaknessAnalyzer(),
      recommendationEngine: const RecommendationEngine(),
      adaptiveDrillEngine: const AdaptiveDrillEngine(),
    );
    await tester.pumpWidget(
      ExamCoachApp(
        learningFlowCubit: cubit,
        authCubit: AuthCubit.unavailable('Test mode'),
        aiCoachCubit: _testAiCoachCubit(questions),
        subscriptionCubit: _testSubscriptionCubit(),
      ),
    );

    expect(
      find.text('Belajar dengan arah,\nbukan sekadar banyak soal.'),
      findsOneWidget,
    );
    await _tapStartTryout(tester);
    await tester.pumpAndSettle();

    expect(find.text('Ringkasan tryout'), findsOneWidget);
    expect(find.text('6 soal untuk membaca pola awalmu'), findsOneWidget);
    await tester.tap(find.byKey(const Key('begin-session-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('skip-question-button')));
    await tester.pumpAndSettle();

    for (var index = 1; index < 6; index++) {
      await tester.tap(find.byKey(const Key('answer-a')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('submit-answer-button')));
      await tester.pumpAndSettle();
    }

    expect(find.text('Periksa jawaban'), findsOneWidget);
    expect(find.textContaining('5 dijawab • 1 dilewati'), findsOneWidget);
    await tester.tap(find.byKey(const Key('edit-question-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('answer-a')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit-answer-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('6 dijawab • 0 dilewati'), findsOneWidget);
    await tester.tap(find.byKey(const Key('finish-session-button')));
    await tester.pumpAndSettle();

    expect(find.text('Tryout selesai'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('review-answers-button')),
      300,
    );
    await tester.tap(find.byKey(const Key('review-answers-button')));
    await tester.pumpAndSettle();
    expect(find.text('Review jawaban'), findsOneWidget);
    expect(find.text('Pembahasan'), findsWidgets);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded).first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('start-drill-button')),
      300,
    );
    expect(find.text('Rekomendasi berikutnya'), findsOneWidget);
    expect(find.byKey(const Key('start-drill-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('start-drill-button')));
    await tester.pumpAndSettle();

    expect(find.text('DRILL ADAPTIF'), findsOneWidget);
    expect(find.text('1/6'), findsOneWidget);

    for (var index = 0; index < 6; index++) {
      await tester.tap(find.byKey(const Key('answer-a')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('submit-answer-button')));
      await tester.pumpAndSettle();
    }

    expect(find.text('Periksa jawaban'), findsOneWidget);
    await tester.tap(find.byKey(const Key('finish-session-button')));
    await tester.pumpAndSettle();

    expect(find.text('Insight diperbarui'), findsOneWidget);
    expect(
      find.text('Jawaban drill sudah masuk ke profil performamu.'),
      findsOneWidget,
    );
  });
}

AiCoachCubit _testAiCoachCubit(MockQuestionRepository questions) =>
    AiCoachCubit(
      contextBuilder: AiCoachContextBuilder(questions),
      repository: const UnavailableAiCoachRepository('Test mode'),
      cacheStore: MemoryAiCoachCacheStore(),
      userIdentity: UserIdentity(),
      analytics: InMemoryAnalytics(),
    );

SubscriptionCubit _testSubscriptionCubit() => SubscriptionCubit(
  repository: const UnavailableSubscriptionRepository(
    'Subscriptions disabled for tests',
  ),
  userIdentity: UserIdentity(),
  analytics: InMemoryAnalytics(),
);

Future<void> _tapStartTryout(WidgetTester tester) async {
  final button = find.byKey(const Key('start-tryout-button'));
  await tester.scrollUntilVisible(button, 300);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}
