import 'package:exam_coach/features/exam/domain/models/answer_record.dart';
import 'package:exam_coach/features/exam/domain/models/exam_session.dart';
import 'package:exam_coach/features/exam/domain/models/question.dart';
import 'package:exam_coach/learning_engine/models/recommendation.dart';
import 'package:exam_coach/learning_engine/models/score_result.dart';
import 'package:exam_coach/learning_engine/models/weakness_profile.dart';

enum LearningFlowStatus { idle, answering, reviewing, result }

class LearningFlowState {
  const LearningFlowState({
    this.status = LearningFlowStatus.idle,
    this.session,
    this.questions = const [],
    this.currentIndex = 0,
    this.selectedOptionId,
    this.currentAnswers = const [],
    this.answerHistory = const [],
    this.latestScore,
    this.profiles = const [],
    this.previousProfiles = const [],
    this.recommendation,
    this.isSaving = false,
    this.errorMessage,
  });

  final LearningFlowStatus status;
  final ExamSession? session;
  final List<Question> questions;
  final int currentIndex;
  final String? selectedOptionId;
  final List<AnswerRecord> currentAnswers;
  final List<AnswerRecord> answerHistory;
  final ScoreResult? latestScore;
  final List<WeaknessProfile> profiles;
  final List<WeaknessProfile> previousProfiles;
  final LearningRecommendation? recommendation;
  final bool isSaving;
  final String? errorMessage;

  ExamSessionMode get mode => session?.mode ?? ExamSessionMode.tryout;

  bool get hasActiveSession =>
      (status == LearningFlowStatus.answering ||
          status == LearningFlowStatus.reviewing) &&
      session?.status == ExamSessionStatus.active;

  int get answeredCount =>
      currentAnswers.where((answer) => !answer.isSkipped).length;

  int get skippedCount =>
      currentAnswers.where((answer) => answer.isSkipped).length;

  bool get allQuestionsResponded =>
      questions.isNotEmpty && currentAnswers.length == questions.length;

  AnswerRecord? answerFor(String questionId) {
    for (final answer in currentAnswers) {
      if (answer.questionId == questionId) {
        return answer;
      }
    }
    return null;
  }

  Question? get currentQuestion {
    if (questions.isEmpty || currentIndex >= questions.length) {
      return null;
    }
    return questions[currentIndex];
  }

  bool get isLastQuestion =>
      questions.isNotEmpty && currentIndex == questions.length - 1;

  LearningFlowState copyWith({
    LearningFlowStatus? status,
    ExamSession? session,
    bool clearSession = false,
    List<Question>? questions,
    int? currentIndex,
    String? selectedOptionId,
    bool clearSelectedOption = false,
    List<AnswerRecord>? currentAnswers,
    List<AnswerRecord>? answerHistory,
    ScoreResult? latestScore,
    bool clearLatestScore = false,
    List<WeaknessProfile>? profiles,
    List<WeaknessProfile>? previousProfiles,
    LearningRecommendation? recommendation,
    bool clearRecommendation = false,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
  }) {
    return LearningFlowState(
      status: status ?? this.status,
      session: clearSession ? null : session ?? this.session,
      questions: questions ?? this.questions,
      currentIndex: currentIndex ?? this.currentIndex,
      selectedOptionId: clearSelectedOption
          ? null
          : selectedOptionId ?? this.selectedOptionId,
      currentAnswers: currentAnswers ?? this.currentAnswers,
      answerHistory: answerHistory ?? this.answerHistory,
      latestScore: clearLatestScore ? null : latestScore ?? this.latestScore,
      profiles: profiles ?? this.profiles,
      previousProfiles: previousProfiles ?? this.previousProfiles,
      recommendation: clearRecommendation
          ? null
          : recommendation ?? this.recommendation,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}
