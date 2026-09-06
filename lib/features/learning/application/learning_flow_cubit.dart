import 'package:exam_coach/analytics/analytics_events.dart';
import 'package:exam_coach/features/exam/domain/models/answer_record.dart';
import 'package:exam_coach/features/exam/domain/models/exam_session.dart';
import 'package:exam_coach/features/exam/domain/models/question.dart';
import 'package:exam_coach/features/exam/domain/repositories/question_repository.dart';
import 'package:exam_coach/features/learning/application/learning_flow_state.dart';
import 'package:exam_coach/features/learning/data/transient_learning_persistence_repository.dart';
import 'package:exam_coach/features/learning/domain/repositories/learning_persistence_repository.dart';
import 'package:exam_coach/learning_engine/adaptive_drill_engine.dart';
import 'package:exam_coach/learning_engine/recommendation_engine.dart';
import 'package:exam_coach/learning_engine/scoring_engine.dart';
import 'package:exam_coach/learning_engine/weakness_analyzer.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LearningFlowCubit extends Cubit<LearningFlowState> {
  factory LearningFlowCubit({
    required QuestionRepository questionRepository,
    required ScoringEngine scoringEngine,
    required WeaknessAnalyzer weaknessAnalyzer,
    required RecommendationEngine recommendationEngine,
    required AdaptiveDrillEngine adaptiveDrillEngine,
    LearningPersistenceRepository? persistenceRepository,
    AnalyticsTracker? analytics,
  }) {
    return LearningFlowCubit._(
      questionRepository,
      scoringEngine,
      weaknessAnalyzer,
      recommendationEngine,
      adaptiveDrillEngine,
      persistenceRepository ?? TransientLearningPersistenceRepository(),
      analytics ?? InMemoryAnalytics(),
    );
  }

  LearningFlowCubit._(
    this._questionRepository,
    this._scoringEngine,
    this._weaknessAnalyzer,
    this._recommendationEngine,
    this._adaptiveDrillEngine,
    this._persistenceRepository,
    this.analytics,
  ) : super(const LearningFlowState());

  final QuestionRepository _questionRepository;
  final ScoringEngine _scoringEngine;
  final WeaknessAnalyzer _weaknessAnalyzer;
  final RecommendationEngine _recommendationEngine;
  final AdaptiveDrillEngine _adaptiveDrillEngine;
  final LearningPersistenceRepository _persistenceRepository;
  final AnalyticsTracker analytics;

  DateTime _questionStartedAt = DateTime.now();

  Future<void> restore() async {
    final snapshot = await _persistenceRepository.loadSnapshot();
    final activeSession = snapshot.activeSession;
    if (activeSession == null) {
      emit(
        LearningFlowState(
          answerHistory: snapshot.answerHistory,
          latestScore: snapshot.latestScore,
          profiles: snapshot.profiles,
          recommendation: snapshot.recommendation,
        ),
      );
      return;
    }

    final questionsById = {
      for (final question in _questionRepository.allQuestions)
        question.id: question,
    };
    final questions = [
      for (final id in activeSession.questionIds) ?questionsById[id],
    ];
    if (questions.length != activeSession.questionIds.length ||
        activeSession.currentIndex >= questions.length) {
      emit(
        LearningFlowState(
          answerHistory: snapshot.answerHistory,
          latestScore: snapshot.latestScore,
          profiles: snapshot.profiles,
          recommendation: snapshot.recommendation,
          errorMessage:
              'Sesi tersimpan tidak dapat dipulihkan karena paket soal berubah.',
        ),
      );
      return;
    }

    _questionStartedAt = DateTime.now();
    emit(
      LearningFlowState(
        status: LearningFlowStatus.answering,
        session: activeSession,
        questions: List.unmodifiable(questions),
        currentIndex: activeSession.currentIndex,
        currentAnswers: snapshot.activeAnswers,
        answerHistory: snapshot.answerHistory,
        latestScore: snapshot.latestScore,
        profiles: snapshot.profiles,
        recommendation: snapshot.recommendation,
      ),
    );
  }

  Future<bool> startTryout() async {
    final questions = _questionRepository.initialTryoutQuestions;
    if (questions.isEmpty || state.isSaving) {
      return false;
    }
    return _startSession(
      mode: ExamSessionMode.tryout,
      questions: questions,
      startEvent: AnalyticsEvents.practiceStarted,
    );
  }

  Future<bool> startRecommendedDrill({int questionCount = 6}) async {
    if (state.profiles.isEmpty || state.isSaving) {
      return false;
    }
    final selectedQuestions = _adaptiveDrillEngine.select(
      questions: _questionRepository.allQuestions,
      profiles: state.profiles,
      previouslyAttemptedQuestionIds: state.answerHistory
          .map((answer) => answer.questionId)
          .toSet(),
      count: questionCount,
    );
    if (selectedQuestions.isEmpty) {
      return false;
    }

    await _trackSafely(
      AnalyticsEvents.recommendationClicked,
      properties: {
        'target': state.recommendation?.targetTaxonomyId ?? 'unknown',
      },
    );
    return _startSession(
      mode: ExamSessionMode.adaptiveDrill,
      questions: selectedQuestions,
      startEvent: AnalyticsEvents.drillStarted,
    );
  }

  Future<bool> _startSession({
    required ExamSessionMode mode,
    required List<Question> questions,
    required String startEvent,
  }) async {
    final now = DateTime.now().toUtc();
    final session = ExamSession(
      id: 'session_${now.microsecondsSinceEpoch}',
      userId: 'local_user',
      testId: questions.first.taxonomy.testId,
      mode: mode,
      status: ExamSessionStatus.active,
      questionIds: List.unmodifiable(questions.map((question) => question.id)),
      currentIndex: 0,
      startedAt: now,
      updatedAt: now,
      syncVersion: 1,
    );

    emit(state.copyWith(isSaving: true, clearError: true));
    try {
      await _persistenceRepository.startSession(session);
      _questionStartedAt = DateTime.now();
      emit(
        LearningFlowState(
          status: LearningFlowStatus.answering,
          session: session,
          questions: List.unmodifiable(questions),
          answerHistory: state.answerHistory,
          latestScore: state.latestScore,
          profiles: state.profiles,
          previousProfiles: state.profiles,
          recommendation: state.recommendation,
        ),
      );
      await _trackSafely(
        startEvent,
        properties: {'mode': mode.name, 'sessionId': session.id},
      );
      return true;
    } on Object catch (error) {
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: 'Sesi tidak dapat disimpan: $error',
        ),
      );
      return false;
    }
  }

  void selectOption(String optionId) {
    if (state.status != LearningFlowStatus.answering || state.isSaving) {
      return;
    }
    emit(state.copyWith(selectedOptionId: optionId, clearError: true));
  }

  Future<bool> submitCurrentAnswer({Duration? timeSpent}) async {
    final question = state.currentQuestion;
    final selectedOptionId = state.selectedOptionId;
    final session = state.session;
    if (question == null ||
        selectedOptionId == null ||
        session == null ||
        state.isSaving) {
      return false;
    }

    final now = DateTime.now().toUtc();
    final answer = AnswerRecord(
      questionId: question.id,
      selectedOptionId: selectedOptionId,
      timeSpent: timeSpent ?? DateTime.now().difference(_questionStartedAt),
      answeredAt: now,
    );
    final currentAnswers = [...state.currentAnswers, answer];
    final updatedSession = session.copyWith(
      currentIndex: state.currentIndex + 1,
      updatedAt: now,
      syncVersion: session.syncVersion + 1,
    );
    emit(state.copyWith(isSaving: true, clearError: true));

    try {
      await _persistenceRepository.saveAnswer(
        session: updatedSession,
        answer: answer,
        correctOptionId: question.correctOptionId,
        isCorrect: selectedOptionId == question.correctOptionId,
      );
      await _trackSafely(
        AnalyticsEvents.questionAnswered,
        properties: {
          'sessionId': session.id,
          'questionId': question.id,
          'taxonomyNodeId': question.taxonomy.topicId,
          'isCorrect': selectedOptionId == question.correctOptionId,
          'timeSpentMs': answer.timeSpent.inMilliseconds,
        },
      );

      if (!state.isLastQuestion) {
        _questionStartedAt = DateTime.now();
        emit(
          state.copyWith(
            session: updatedSession,
            currentIndex: state.currentIndex + 1,
            clearSelectedOption: true,
            currentAnswers: currentAnswers,
            isSaving: false,
          ),
        );
        return false;
      }

      await _completeSession(currentAnswers, updatedSession);
      return true;
    } on Object catch (error) {
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: 'Jawaban tidak dapat disimpan: $error',
        ),
      );
      return false;
    }
  }

  Future<void> _completeSession(
    List<AnswerRecord> currentAnswers,
    ExamSession activeSession,
  ) async {
    final answerHistory = [...state.answerHistory, ...currentAnswers];
    final score = _scoringEngine.calculate(
      questions: state.questions,
      answers: currentAnswers,
    );
    final previousProfiles = state.profiles;
    final profiles = _weaknessAnalyzer.analyze(
      questions: _questionRepository.allQuestions,
      answers: answerHistory,
      previousProfiles: previousProfiles,
    );
    final recommendation = _recommendationEngine.generate(profiles);
    final now = DateTime.now().toUtc();
    final completedSession = activeSession.copyWith(
      status: ExamSessionStatus.completed,
      currentIndex: state.questions.length,
      updatedAt: now,
      endedAt: now,
      score: score.percentage,
      syncVersion: activeSession.syncVersion + 1,
    );

    await _persistenceRepository.completeSession(
      session: completedSession,
      score: score,
      profiles: profiles,
      recommendation: recommendation,
    );
    emit(
      state.copyWith(
        status: LearningFlowStatus.result,
        session: completedSession,
        currentAnswers: currentAnswers,
        answerHistory: answerHistory,
        latestScore: score,
        previousProfiles: previousProfiles,
        profiles: profiles,
        recommendation: recommendation,
        clearSelectedOption: true,
        isSaving: false,
      ),
    );

    final completionEvent = completedSession.mode == ExamSessionMode.tryout
        ? AnalyticsEvents.practiceCompleted
        : AnalyticsEvents.drillCompleted;
    await _trackSafely(
      completionEvent,
      properties: {'sessionId': completedSession.id, 'score': score.percentage},
    );
    await _trackSafely(
      AnalyticsEvents.resultViewed,
      properties: {'sessionId': completedSession.id},
    );
    await _trackSafely(
      AnalyticsEvents.weaknessViewed,
      properties: {'sessionId': completedSession.id},
    );
    if (recommendation != null) {
      await _trackSafely(
        AnalyticsEvents.recommendationViewed,
        properties: {
          'sessionId': completedSession.id,
          'target': recommendation.targetTaxonomyId,
        },
      );
    }
  }

  Future<void> _trackSafely(
    String event, {
    Map<String, Object> properties = const {},
  }) async {
    try {
      await analytics.track(event, properties: properties);
    } on Object {
      // Analytics must never block the deterministic learning loop.
    }
  }
}
