import 'package:exam_coach/features/exam/domain/models/answer_record.dart';
import 'package:exam_coach/features/exam/domain/models/exam_session.dart';
import 'package:exam_coach/features/learning/domain/models/learning_persistence_snapshot.dart';
import 'package:exam_coach/features/learning/domain/repositories/learning_persistence_repository.dart';
import 'package:exam_coach/learning_engine/models/recommendation.dart';
import 'package:exam_coach/learning_engine/models/score_result.dart';
import 'package:exam_coach/learning_engine/models/weakness_profile.dart';

class TransientLearningPersistenceRepository
    implements LearningPersistenceRepository {
  @override
  Future<void> completeSession({
    required ExamSession session,
    required ScoreResult score,
    required List<WeaknessProfile> profiles,
    required LearningRecommendation? recommendation,
  }) async {}

  @override
  Future<void> endSession(ExamSession session) async {}

  @override
  Future<LearningPersistenceSnapshot> loadSnapshot() async =>
      const LearningPersistenceSnapshot();

  @override
  Future<void> saveAnswer({
    required ExamSession session,
    required AnswerRecord answer,
    required String correctOptionId,
    required bool isCorrect,
  }) async {}

  @override
  Future<void> startSession(ExamSession session) async {}

  @override
  Future<void> updateSessionCursor(ExamSession session) async {}
}
