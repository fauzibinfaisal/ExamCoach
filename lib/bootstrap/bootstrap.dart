import 'package:exam_coach/app/app.dart';
import 'package:exam_coach/analytics/local_analytics.dart';
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
import 'package:flutter/widgets.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final seedRepository = MockQuestionRepository();
  late final LearningFlowCubit learningFlowCubit;
  try {
    final database = await ExamCoachDatabase.openDefault();
    final questionRepository = LocalQuestionRepository(database);
    await questionRepository.initializeWithSeed(seedRepository);
    final persistenceRepository = LocalLearningPersistenceRepository(database);
    learningFlowCubit = _createCubit(
      questionRepository,
      persistenceRepository: persistenceRepository,
      analytics: LocalAnalytics(database),
    );
    await learningFlowCubit.restore();
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
  }

  runApp(ExamCoachApp(learningFlowCubit: learningFlowCubit));
}

LearningFlowCubit _createCubit(
  QuestionRepository questionRepository, {
  LocalLearningPersistenceRepository? persistenceRepository,
  LocalAnalytics? analytics,
}) {
  return LearningFlowCubit(
    questionRepository: questionRepository,
    scoringEngine: const ScoringEngine(),
    weaknessAnalyzer: const WeaknessAnalyzer(),
    recommendationEngine: const RecommendationEngine(),
    adaptiveDrillEngine: const AdaptiveDrillEngine(),
    persistenceRepository: persistenceRepository,
    analytics: analytics,
  );
}
