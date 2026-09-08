import 'package:exam_coach/app/app.dart';
import 'package:exam_coach/analytics/local_analytics.dart';
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
import 'package:flutter/widgets.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final seedRepository = MockQuestionRepository();
  late final LearningFlowCubit learningFlowCubit;
  late final AuthCubit authCubit;
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
    learningFlowCubit = _createCubit(
      questionRepository,
      persistenceRepository: persistenceRepository,
      analytics: LocalAnalytics(database, userIdentity: userIdentity),
      userIdentity: userIdentity,
    );
    await learningFlowCubit.restore();

    final firebase = await const FirebaseRuntimeInitializer().initialize();
    final services = firebase.services;
    if (services == null) {
      authCubit = AuthCubit.unavailable(firebase.message);
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
    learningFlowCubit = _createCubit(seedRepository);
    authCubit = AuthCubit.unavailable(
      'Penyimpanan akun tidak tersedia; mode belajar sementara tetap aktif.',
    );
  }

  runApp(
    ExamCoachApp(learningFlowCubit: learningFlowCubit, authCubit: authCubit),
  );
}

LearningFlowCubit _createCubit(
  QuestionRepository questionRepository, {
  LocalLearningPersistenceRepository? persistenceRepository,
  LocalAnalytics? analytics,
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
