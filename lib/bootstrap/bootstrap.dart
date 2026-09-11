import 'package:exam_coach/app/app.dart';
import 'package:exam_coach/analytics/analytics_events.dart';
import 'package:exam_coach/analytics/local_analytics.dart';
import 'package:exam_coach/features/ai_coach/application/ai_coach_context_builder.dart';
import 'package:exam_coach/features/ai_coach/application/ai_coach_cubit.dart';
import 'package:exam_coach/features/ai_coach/data/firebase_ai_coach_repository.dart';
import 'package:exam_coach/features/ai_coach/data/local_ai_coach_cache_store.dart';
import 'package:exam_coach/features/ai_coach/domain/ai_coach_cache_store.dart';
import 'package:exam_coach/features/ai_coach/domain/ai_coach_repository.dart';
import 'package:exam_coach/features/auth/application/auth_cubit.dart';
import 'package:exam_coach/features/auth/data/firebase_auth_repository.dart';
import 'package:exam_coach/features/auth/data/local_account_data_store.dart';
import 'package:exam_coach/features/auth/domain/user_identity.dart';
import 'package:exam_coach/features/exam/data/bundled_question_bank_loader.dart';
import 'package:exam_coach/features/exam/data/local_question_repository.dart';
import 'package:exam_coach/features/exam/data/mock_question_repository.dart';
import 'package:exam_coach/features/exam/domain/repositories/question_repository.dart';
import 'package:exam_coach/features/learning/application/learning_flow_cubit.dart';
import 'package:exam_coach/features/learning/data/local_learning_persistence_repository.dart';
import 'package:exam_coach/learning_engine/adaptive_drill_engine.dart';
import 'package:exam_coach/learning_engine/recommendation_engine.dart';
import 'package:exam_coach/learning_engine/scoring_engine.dart';
import 'package:exam_coach/learning_engine/weakness_analyzer.dart';
import 'package:exam_coach/services/database/exam_coach_database.dart';
import 'package:exam_coach/services/firebase/firebase_runtime.dart';
import 'package:exam_coach/services/sync/application/sync_coordinator.dart';
import 'package:exam_coach/services/sync/application/sync_worker.dart';
import 'package:exam_coach/services/sync/data/connectivity_plus_monitor.dart';
import 'package:exam_coach/services/sync/data/firebase_sync_gateway.dart';
import 'package:exam_coach/features/subscription/application/subscription_cubit.dart';
import 'package:exam_coach/features/subscription/data/revenuecat_subscription_repository.dart';
import 'package:exam_coach/features/subscription/data/subscription_runtime_config.dart';
import 'package:exam_coach/features/subscription/domain/subscription_repository.dart';
import 'package:flutter/widgets.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final seedRepository = MockQuestionRepository();
  late final LearningFlowCubit learningFlowCubit;
  late final AuthCubit authCubit;
  late final AiCoachCubit aiCoachCubit;
  late final SubscriptionCubit subscriptionCubit;
  try {
    final bundledBank = await BundledQuestionBankLoader().load();
    final database = await ExamCoachDatabase.openDefault();
    final questionRepository = LocalQuestionRepository(database);
    await questionRepository.initializeWithSeed(
      seedRepository,
      importedPacks: bundledBank.packs,
      activePackId: bundledBank.activePackId,
    );
    final accountDataStore = LocalAccountDataStore(database);
    final userIdentity = UserIdentity(
      boundUserId: await accountDataStore.loadBoundUserId(),
    );
    final persistenceRepository = LocalLearningPersistenceRepository(database);
    final analytics = LocalAnalytics(database, userIdentity: userIdentity);
    learningFlowCubit = _createCubit(
      questionRepository,
      persistenceRepository: persistenceRepository,
      analytics: analytics,
      userIdentity: userIdentity,
    );
    await learningFlowCubit.restore();

    final firebase = await const FirebaseRuntimeInitializer().initialize();
    final services = firebase.services;
    if (services == null) {
      authCubit = AuthCubit.unavailable(firebase.message);
      aiCoachCubit = _createAiCoachCubit(
        questionRepository: questionRepository,
        repository: UnavailableAiCoachRepository(firebase.message),
        cacheStore: LocalAiCoachCacheStore(database),
        userIdentity: userIdentity,
        analytics: analytics,
      );
      subscriptionCubit = _createSubscriptionCubit(
        repository: UnavailableSubscriptionRepository(firebase.message),
        userIdentity: userIdentity,
        analytics: analytics,
      );
    } else {
      final connectivity = ConnectivityPlusMonitor();
      final gateway = FirebaseSyncGateway(
        functions: services.functions,
        auth: services.auth,
      );
      final syncCoordinator = SyncCoordinator(
        connectivityMonitor: connectivity,
        syncRunner: SyncWorker(
          outboxRepository: persistenceRepository,
          remoteGateway: gateway,
          connectivityMonitor: connectivity,
        ),
        onError: (error, stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'ExamCoach sync',
              context: ErrorDescription('while synchronizing Firebase data'),
            ),
          );
        },
      );
      authCubit = AuthCubit(
        authRepository: FirebaseAuthRepository(services.auth),
        accountDataStore: accountDataStore,
        userIdentity: userIdentity,
        learningFlowCubit: learningFlowCubit,
        recoveryGateway: gateway,
        syncCoordinator: syncCoordinator,
      );
      aiCoachCubit = _createAiCoachCubit(
        questionRepository: questionRepository,
        repository: FirebaseAiCoachRepository(
          functions: services.functions,
          auth: services.auth,
        ),
        cacheStore: LocalAiCoachCacheStore(database),
        userIdentity: userIdentity,
        analytics: analytics,
      );
      final subscriptionConfig = SubscriptionRuntimeConfig.fromEnvironment();
      final subscriptionRepository = RevenueCatSubscriptionRepository(
        functions: services.functions,
        auth: services.auth,
        config: subscriptionConfig,
      );
      subscriptionCubit = _createSubscriptionCubit(
        repository: subscriptionRepository.isAvailable
            ? subscriptionRepository
            : UnavailableSubscriptionRepository(
                subscriptionRepository.unavailableReason,
              ),
        userIdentity: userIdentity,
        analytics: analytics,
      );
      await authCubit.start();
    }
  } on Object catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'ExamCoach bootstrap',
        context: ErrorDescription('while opening local persistence'),
      ),
    );
    final userIdentity = UserIdentity();
    final analytics = InMemoryAnalytics();
    learningFlowCubit = _createCubit(
      seedRepository,
      analytics: analytics,
      userIdentity: userIdentity,
    );
    authCubit = AuthCubit.unavailable(
      'Penyimpanan akun tidak tersedia; mode belajar sementara tetap aktif.',
    );
    aiCoachCubit = _createAiCoachCubit(
      questionRepository: seedRepository,
      repository: const UnavailableAiCoachRepository(
        'AI Coach tidak tersedia tanpa penyimpanan lokal yang aman.',
      ),
      cacheStore: MemoryAiCoachCacheStore(),
      userIdentity: userIdentity,
      analytics: analytics,
    );
    subscriptionCubit = _createSubscriptionCubit(
      repository: const UnavailableSubscriptionRepository(
        'Langganan tidak tersedia tanpa penyimpanan dan akun yang aman.',
      ),
      userIdentity: userIdentity,
      analytics: analytics,
    );
  }

  runApp(
    ExamCoachApp(
      learningFlowCubit: learningFlowCubit,
      authCubit: authCubit,
      aiCoachCubit: aiCoachCubit,
      subscriptionCubit: subscriptionCubit,
    ),
  );
}

LearningFlowCubit _createCubit(
  QuestionRepository questionRepository, {
  LocalLearningPersistenceRepository? persistenceRepository,
  AnalyticsTracker? analytics,
  UserIdentity? userIdentity,
}) {
  return LearningFlowCubit(
    questionRepository: questionRepository,
    scoringEngine: const ScoringEngine(),
    weaknessAnalyzer: const WeaknessAnalyzer(),
    recommendationEngine: const RecommendationEngine(),
    adaptiveDrillEngine: const AdaptiveDrillEngine(),
    persistenceRepository: persistenceRepository,
    analytics: analytics,
    userIdentity: userIdentity,
  );
}

AiCoachCubit _createAiCoachCubit({
  required QuestionRepository questionRepository,
  required AiCoachRepository repository,
  required AiCoachCacheStore cacheStore,
  required UserIdentity userIdentity,
  required AnalyticsTracker analytics,
}) => AiCoachCubit(
  contextBuilder: AiCoachContextBuilder(questionRepository),
  repository: repository,
  cacheStore: cacheStore,
  userIdentity: userIdentity,
  analytics: analytics,
);

SubscriptionCubit _createSubscriptionCubit({
  required SubscriptionRepository repository,
  required UserIdentity userIdentity,
  required AnalyticsTracker analytics,
}) => SubscriptionCubit(
  repository: repository,
  userIdentity: userIdentity,
  analytics: analytics,
);
