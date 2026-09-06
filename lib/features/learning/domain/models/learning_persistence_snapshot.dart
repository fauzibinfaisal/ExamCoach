import 'package:exam_coach/features/exam/domain/models/answer_record.dart';
import 'package:exam_coach/features/exam/domain/models/exam_session.dart';
import 'package:exam_coach/learning_engine/models/recommendation.dart';
import 'package:exam_coach/learning_engine/models/score_result.dart';
import 'package:exam_coach/learning_engine/models/weakness_profile.dart';

class LearningPersistenceSnapshot {
  const LearningPersistenceSnapshot({
    this.activeSession,
    this.activeAnswers = const [],
    this.answerHistory = const [],
    this.latestScore,
    this.profiles = const [],
    this.recommendation,
  });

  final ExamSession? activeSession;
  final List<AnswerRecord> activeAnswers;
  final List<AnswerRecord> answerHistory;
  final ScoreResult? latestScore;
  final List<WeaknessProfile> profiles;
  final LearningRecommendation? recommendation;
}
