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
}
