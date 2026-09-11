import 'package:exam_coach/analytics/analytics_events.dart';
import 'package:exam_coach/features/ai_coach/application/ai_coach_context_builder.dart';
import 'package:exam_coach/features/ai_coach/application/ai_coach_cubit.dart';
import 'package:exam_coach/features/ai_coach/application/ai_coach_state.dart';
import 'package:exam_coach/features/ai_coach/domain/ai_coach_cache_store.dart';
import 'package:exam_coach/features/ai_coach/domain/ai_coach_models.dart';
import 'package:exam_coach/features/ai_coach/domain/ai_coach_repository.dart';
import 'package:exam_coach/features/auth/domain/user_identity.dart';
import 'package:exam_coach/features/exam/data/mock_question_repository.dart';
import 'package:exam_coach/features/exam/domain/models/exam_session.dart';
import 'package:exam_coach/features/learning/application/learning_flow_state.dart';
import 'package:exam_coach/learning_engine/models/recommendation.dart';
import 'package:exam_coach/learning_engine/models/score_result.dart';
import 'package:exam_coach/learning_engine/models/weakness_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 11, 10);

  test('normalizes context before hashing across Flutter and backend', () {
    final state = _learningState(
      completedAt: DateTime.utc(2026, 9, 11, 9, 30, 0, 123, 456),
    );
    final context = AiCoachContextBuilder(
      MockQuestionRepository(),
    ).build(state)!;
    final sameMillisecond = AiCoachContext(
      sourceSessionId: context.sourceSessionId,
      examId: context.examId,
      testId: context.testId,
      scorePercentage: context.scorePercentage,
      completedAt: DateTime.utc(2026, 9, 11, 9, 30, 0, 123),
      topWeaknesses: context.topWeaknesses,
      recommendation: context.recommendation,
    );

    expect(context.contextJson['completedAt'], '2026-09-11T09:30:00.123Z');
    expect(context.topWeaknesses.single.label, 'Perbandingan');
    expect(context.topWeaknesses.single.evidence.single, 'akurasi rendah');
    expect(context.recommendation.reason, 'Perlu latihan terarah.');
    expect(context.contextKey, sameMillisecond.contextKey);
  });

  test(
    'loads quota, generates, caches, and tracks structured insight',
    () async {
      final identity = UserIdentity(boundUserId: 'user_123')
        ..bindAuthenticatedUser('user_123');
      final analytics = InMemoryAnalytics();
      final cache = MemoryAiCoachCacheStore();
      final repository = _FakeAiCoachRepository(now: now);
      final cubit = AiCoachCubit(
        contextBuilder: AiCoachContextBuilder(MockQuestionRepository()),
        repository: repository,
        cacheStore: cache,
        userIdentity: identity,
        analytics: analytics,
        now: () => now,
      );
      addTearDown(cubit.close);

      await cubit.refresh(_learningState());
      expect(cubit.state.status, AiCoachStatus.ready);
      expect(cubit.state.quota?.remaining, 2);

      await cubit.generate();
      expect(cubit.state.status, AiCoachStatus.success);
      expect(cubit.state.insight?.studyPlan, hasLength(1));
      expect(cubit.state.quota?.used, 1);

      await cubit.recordViewed();
      await cubit.recordViewed();
      expect(
        analytics.events.map((event) => event.name),
        containsAll([
          AnalyticsEvents.aiInsightRequested,
          AnalyticsEvents.aiInsightGenerated,
          AnalyticsEvents.aiInsightViewed,
        ]),
      );
      expect(
        analytics.events.where(
          (event) => event.name == AnalyticsEvents.aiInsightViewed,
        ),
        hasLength(1),
      );

      final offlineCubit = AiCoachCubit(
        contextBuilder: AiCoachContextBuilder(MockQuestionRepository()),
        repository: const UnavailableAiCoachRepository('offline'),
        cacheStore: cache,
        userIdentity: identity,
        analytics: InMemoryAnalytics(),
        now: () => now,
      );
      addTearDown(offlineCubit.close);
      await offlineCubit.refresh(_learningState());

      expect(offlineCubit.state.status, AiCoachStatus.unavailable);
      expect(offlineCubit.state.insight?.fromServerCache, isTrue);
      expect(offlineCubit.state.message, contains('tersimpan'));
    },
  );

  test('shows quota exhaustion without losing deterministic context', () async {
    final identity = UserIdentity(boundUserId: 'user_123')
      ..bindAuthenticatedUser('user_123');
    final analytics = InMemoryAnalytics();
    final repository = _FakeAiCoachRepository(
      now: now,
      generateFailure: AiCoachFailure(
        AiCoachFailureCode.quotaExhausted,
        'Kuota habis.',
        quota: _quota(now, used: 2),
      ),
    );
    final cubit = AiCoachCubit(
      contextBuilder: AiCoachContextBuilder(MockQuestionRepository()),
      repository: repository,
      cacheStore: MemoryAiCoachCacheStore(),
      userIdentity: identity,
      analytics: analytics,
      now: () => now,
    );
    addTearDown(cubit.close);

    await cubit.refresh(_learningState());
    await cubit.generate();

    expect(cubit.state.status, AiCoachStatus.quotaExhausted);
    expect(cubit.state.context, isNotNull);
    expect(cubit.state.quota?.remaining, 0);
    expect(
      analytics.events.map((event) => event.name),
      contains(AnalyticsEvents.aiQuotaExhausted),
    );
  });
}

class _FakeAiCoachRepository implements AiCoachRepository {
  _FakeAiCoachRepository({required this.now, this.generateFailure});

  final DateTime now;
  final AiCoachFailure? generateFailure;

  @override
  bool get isAvailable => true;

  @override
  Future<AiCoachQuotaStatus> getStatus() async => _quota(now);

  @override
  Future<AiCoachGenerationResult> generate(AiCoachContext context) async {
    final failure = generateFailure;
    if (failure != null) throw failure;
    return AiCoachGenerationResult(
      insight: AiCoachInsight(
        contextKey: context.contextKey,
        summary: 'Fokus utama sudah teridentifikasi.',
        weaknessExplanation: 'Bukti latihan menunjukkan satu area prioritas.',
        whyItMatters: 'Area ini mendukung peningkatan hasil berikutnya.',
        studyPlan: const [
          AiCoachStudyPlanItem(
            title: 'Latihan terarah',
            action: 'Kerjakan satu set latihan rekomendasi.',
            durationMinutes: 20,
          ),
        ],
        motivation: 'Lanjutkan secara konsisten.',
        generatedAt: now,
        expiresAt: now.add(const Duration(hours: 24)),
        provider: 'fake',
        model: 'fake_v1',
        promptVersion: 'ai_coach_v1',
      ),
      quota: _quota(now, used: 1),
    );
  }
}

AiCoachQuotaStatus _quota(DateTime now, {int used = 0}) => AiCoachQuotaStatus(
  enabled: true,
  policyVersion: 'policy_v1',
  planId: 'premium',
  entitlementStatus: 'active',
  dailyLimit: 2,
  used: used,
  resetsAt: now.add(const Duration(days: 1)),
);

LearningFlowState _learningState({DateTime? completedAt}) {
  final endedAt = completedAt ?? DateTime.utc(2026, 9, 11, 9, 30);
  return LearningFlowState(
    latestCompletedSession: ExamSession(
      id: 'session_123',
      userId: 'user_123',
      testId: 'test_tiu',
      mode: ExamSessionMode.tryout,
      status: ExamSessionStatus.completed,
      questionIds: const ['q_ratio_01'],
      currentIndex: 1,
      startedAt: endedAt.subtract(const Duration(minutes: 10)),
      updatedAt: endedAt,
      endedAt: endedAt,
      score: 0,
      syncVersion: 2,
    ),
    latestScore: const ScoreResult(
      evaluations: [
        AnswerEvaluation(
          questionId: 'q_ratio_01',
          selectedOptionId: 'a',
          correctOptionId: 'b',
          isCorrect: false,
        ),
      ],
    ),
    profiles: const [
      WeaknessProfile(
        taxonomyNodeId: 'topic_ratio',
        taxonomyLabel: ' Perbandingan ',
        weaknessScore: 0.8,
        confidence: 0.7,
        sampleSize: 4,
        trend: PerformanceTrend.declining,
        tier: WeaknessTier.weak,
        evidence: [' akurasi rendah '],
      ),
    ],
    recommendation: const LearningRecommendation(
      type: RecommendationType.adaptiveDrill,
      targetTaxonomyId: 'topic_ratio',
      targetLabel: ' Perbandingan ',
      priority: 1,
      reasonCode: RecommendationReasonCode.repeatedLowAccuracy,
      reason: ' Perlu latihan terarah. ',
      expectedBenefit: ' Meningkatkan akurasi. ',
      estimatedEffort: Duration(minutes: 20),
      confidence: 0.7,
    ),
  );
}
