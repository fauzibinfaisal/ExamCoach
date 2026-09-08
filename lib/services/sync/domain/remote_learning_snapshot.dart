import 'package:exam_coach/features/exam/domain/models/exam_session.dart';

class RemoteAnswerRecord {
  const RemoteAnswerRecord({
    required this.sessionId,
    required this.questionId,
    required this.position,
    required this.selectedOptionId,
    required this.timeSpent,
    required this.changedAnswer,
    required this.answeredAt,
  });

  final String sessionId;
  final String questionId;
  final int position;
  final String? selectedOptionId;
  final Duration timeSpent;
  final bool changedAnswer;
  final DateTime answeredAt;
}

class RemoteLearningSnapshot {
  RemoteLearningSnapshot({
    required this.userId,
    required this.remoteRevision,
    required Iterable<ExamSession> sessions,
    required Iterable<RemoteAnswerRecord> answers,
  }) : sessions = List.unmodifiable(sessions),
       answers = List.unmodifiable(answers);

  final String userId;
  final int remoteRevision;
  final List<ExamSession> sessions;
  final List<RemoteAnswerRecord> answers;
}

abstract interface class RemoteRecoveryGateway {
  Future<RemoteLearningSnapshot> pullSnapshot();
}
