import 'package:exam_coach/features/exam/domain/models/answer_record.dart';
import 'package:exam_coach/features/exam/domain/models/exam_session.dart';
import 'package:exam_coach/features/learning/domain/models/learning_persistence_snapshot.dart';
import 'package:exam_coach/learning_engine/models/recommendation.dart';
import 'package:exam_coach/learning_engine/models/score_result.dart';
import 'package:exam_coach/learning_engine/models/weakness_profile.dart';

abstract interface class LearningPersistenceRepository {
  Future<LearningPersistenceSnapshot> loadSnapshot();

  Future<void> startSession(ExamSession session);

  Future<void> saveAnswer({
    required ExamSession session,
    required AnswerRecord answer,
    required String correctOptionId,
    required bool isCorrect,
  });

  Future<void> updateSessionCursor(ExamSession session);

  Future<void> endSession(ExamSession session);

  Future<void> completeSession({
    required ExamSession session,
    required ScoreResult score,
    required List<WeaknessProfile> profiles,
    required LearningRecommendation? recommendation,
  });
}
