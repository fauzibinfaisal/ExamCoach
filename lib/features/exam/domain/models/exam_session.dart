enum ExamSessionMode { tryout, adaptiveDrill }

enum ExamSessionStatus { active, completed, cancelled, expired }

class ExamSession {
  const ExamSession({
    required this.id,
    required this.userId,
    required this.testId,
    required this.mode,
    required this.status,
    required this.questionIds,
    required this.currentIndex,
    required this.startedAt,
    required this.updatedAt,
    required this.syncVersion,
    this.endedAt,
    this.score,
  });

  final String id;
  final String userId;
  final String testId;
  final ExamSessionMode mode;
  final ExamSessionStatus status;
  final List<String> questionIds;
  final int currentIndex;
  final DateTime startedAt;
  final DateTime updatedAt;
  final DateTime? endedAt;
  final int? score;
  final int syncVersion;

  ExamSession copyWith({
    ExamSessionStatus? status,
    int? currentIndex,
    DateTime? updatedAt,
    DateTime? endedAt,
    int? score,
    int? syncVersion,
  }) {
    return ExamSession(
      id: id,
      userId: userId,
      testId: testId,
      mode: mode,
      status: status ?? this.status,
      questionIds: questionIds,
      currentIndex: currentIndex ?? this.currentIndex,
      startedAt: startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      endedAt: endedAt ?? this.endedAt,
      score: score ?? this.score,
      syncVersion: syncVersion ?? this.syncVersion,
    );
  }
}
