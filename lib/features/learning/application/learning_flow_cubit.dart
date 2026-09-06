import 'package:exam_coach/analytics/analytics_events.dart';
import 'package:exam_coach/features/exam/domain/models/answer_record.dart';
import 'package:exam_coach/features/exam/domain/models/exam_session.dart';
import 'package:exam_coach/features/exam/domain/models/question.dart';
import 'package:exam_coach/features/exam/domain/repositories/question_repository.dart';
import 'package:exam_coach/features/learning/application/learning_flow_state.dart';
import 'package:exam_coach/features/learning/data/transient_learning_persistence_repository.dart';
import 'package:exam_coach/features/learning/domain/repositories/learning_persistence_repository.dart';
import 'package:exam_coach/features/result/domain/question_review_access_policy.dart';
import 'package:exam_coach/learning_engine/adaptive_drill_engine.dart';
import 'package:exam_coach/learning_engine/recommendation_engine.dart';
import 'package:exam_coach/learning_engine/scoring_engine.dart';
import 'package:exam_coach/learning_engine/weakness_analyzer.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

typedef UtcNow = DateTime Function();

class LearningFlowCubit extends Cubit<LearningFlowState> {
  factory LearningFlowCubit({
    required QuestionRepository questionRepository,
    required ScoringEngine scoringEngine,
    required WeaknessAnalyzer weaknessAnalyzer,
    required RecommendationEngine recommendationEngine,
    required AdaptiveDrillEngine adaptiveDrillEngine,
    LearningPersistenceRepository? persistenceRepository,
    AnalyticsTracker? analytics,
    QuestionReviewAccessPolicy? reviewAccessPolicy,
    Duration sessionExpiry = const Duration(hours: 24),
    UtcNow? now,
  }) {
    return LearningFlowCubit._(
      questionRepository,
      scoringEngine,
      weaknessAnalyzer,
      recommendationEngine,
      adaptiveDrillEngine,
      persistenceRepository ?? TransientLearningPersistenceRepository(),
      analytics ?? InMemoryAnalytics(),
      reviewAccessPolicy ?? const DevelopmentQuestionReviewAccessPolicy(),
      sessionExpiry,
      now ?? () => DateTime.now().toUtc(),
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
    this._reviewAccessPolicy,
    this._sessionExpiry,
    this._now,
  ) : _questionStartedAt = _ensureUtc(_now()),
      super(const LearningFlowState());

  final QuestionRepository _questionRepository;
  final ScoringEngine _scoringEngine;
  final WeaknessAnalyzer _weaknessAnalyzer;
  final RecommendationEngine _recommendationEngine;
  final AdaptiveDrillEngine _adaptiveDrillEngine;
  final LearningPersistenceRepository _persistenceRepository;
  final QuestionReviewAccessPolicy _reviewAccessPolicy;
  final Duration _sessionExpiry;
  final UtcNow _now;
  final AnalyticsTracker analytics;

  DateTime _questionStartedAt;

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

    final now = _utcNow();
    if (now.difference(activeSession.updatedAt) > _sessionExpiry) {
      final expiredSession = activeSession.copyWith(
        status: ExamSessionStatus.expired,
        updatedAt: now,
        endedAt: now,
        syncVersion: activeSession.syncVersion + 1,
      );
      await _persistenceRepository.endSession(expiredSession);
      await _trackSafely(
        AnalyticsEvents.practiceExpired,
        properties: {
          'sessionId': activeSession.id,
          'mode': activeSession.mode.name,
          'inactiveForMs': now
              .difference(activeSession.updatedAt)
              .inMilliseconds,
        },
      );
      emit(
        LearningFlowState(
          answerHistory: snapshot.answerHistory,
          latestScore: snapshot.latestScore,
          profiles: snapshot.profiles,
          recommendation: snapshot.recommendation,
          errorMessage:
              'Sesi sebelumnya kedaluwarsa setelah 24 jam tidak aktif.',
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
        activeSession.currentIndex > questions.length) {
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

    final allResponded = snapshot.activeAnswers.length == questions.length;
    final shouldReview =
        allResponded && activeSession.currentIndex == questions.length;
    final currentIndex = shouldReview
        ? questions.length
        : _recoverQuestionIndex(
            activeSession.currentIndex,
            questions,
            snapshot.activeAnswers,
          );
    final currentAnswer = currentIndex < questions.length
        ? _answerFor(snapshot.activeAnswers, questions[currentIndex].id)
        : null;

    _questionStartedAt = now;
    emit(
      LearningFlowState(
        status: shouldReview
            ? LearningFlowStatus.reviewing
            : LearningFlowStatus.answering,
        session: activeSession.copyWith(currentIndex: currentIndex),
        questions: List.unmodifiable(questions),
        currentIndex: currentIndex,
        selectedOptionId: currentAnswer?.selectedOptionId,
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
          .where((answer) => !answer.isSkipped)
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
    final now = _utcNow();
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
      _questionStartedAt = now;
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
    if (state.selectedOptionId == null) {
      return false;
    }
    return _saveCurrentResponse(
      selectedOptionId: state.selectedOptionId,
      timeSpent: timeSpent,
    );
  }

  Future<bool> skipCurrentQuestion({Duration? timeSpent}) async {
    return _saveCurrentResponse(selectedOptionId: null, timeSpent: timeSpent);
  }

  Future<bool> _saveCurrentResponse({
    required String? selectedOptionId,
    Duration? timeSpent,
  }) async {
    final question = state.currentQuestion;
    final session = state.session;
    if (question == null ||
        session == null ||
        state.status != LearningFlowStatus.answering ||
        state.isSaving) {
      return false;
    }

    final now = _utcNow();
    final existing = state.answerFor(question.id);
    final changed =
        existing != null && existing.selectedOptionId != selectedOptionId;
    final elapsed = timeSpent ?? now.difference(_questionStartedAt);
    final answer = AnswerRecord(
      questionId: question.id,
      selectedOptionId: selectedOptionId,
      timeSpent: (existing?.timeSpent ?? Duration.zero) + elapsed,
      answeredAt: now,
      changedAnswer: (existing?.changedAnswer ?? false) || changed,
    );
    final currentAnswers = _replaceAnswer(state.currentAnswers, answer);
    final readyForReview = currentAnswers.length == state.questions.length;
    final nextIndex = readyForReview
        ? state.questions.length
        : _nextPendingQuestionIndex(
            state.currentIndex,
            state.questions,
            currentAnswers,
          );
    final updatedSession = session.copyWith(
      currentIndex: nextIndex,
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
      await _trackResponse(
        session: session,
        question: question,
        answer: answer,
        existing: existing,
      );

      if (readyForReview) {
        emit(
          state.copyWith(
            status: LearningFlowStatus.reviewing,
            session: updatedSession,
            currentIndex: nextIndex,
            clearSelectedOption: true,
            currentAnswers: currentAnswers,
            isSaving: false,
          ),
        );
        return true;
      }

      _questionStartedAt = now;
      emit(
        state.copyWith(
          status: LearningFlowStatus.answering,
          session: updatedSession,
          currentIndex: nextIndex,
          clearSelectedOption: true,
          currentAnswers: currentAnswers,
          isSaving: false,
        ),
      );
      return false;
    } on Object catch (error) {
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: 'Respons tidak dapat disimpan: $error',
        ),
      );
      return false;
    }
  }

  Future<bool> goToQuestion(int index) async {
    final session = state.session;
    if (session == null ||
        session.status != ExamSessionStatus.active ||
        state.isSaving ||
        index < 0 ||
        index >= state.questions.length) {
      return false;
    }
    final now = _utcNow();
    final updatedSession = session.copyWith(
      currentIndex: index,
      updatedAt: now,
      syncVersion: session.syncVersion + 1,
    );
    emit(state.copyWith(isSaving: true, clearError: true));
    try {
      await _persistenceRepository.updateSessionCursor(updatedSession);
      _questionStartedAt = now;
      final answer = state.answerFor(state.questions[index].id);
      emit(
        state.copyWith(
          status: LearningFlowStatus.answering,
          session: updatedSession,
          currentIndex: index,
          selectedOptionId: answer?.selectedOptionId,
          clearSelectedOption: answer?.selectedOptionId == null,
          isSaving: false,
        ),
      );
      return true;
    } on Object catch (error) {
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: 'Posisi soal tidak dapat disimpan: $error',
        ),
      );
      return false;
    }
  }

  Future<bool> completeCurrentSession() async {
    final session = state.session;
    if (state.status != LearningFlowStatus.reviewing ||
        session == null ||
        !state.allQuestionsResponded ||
        state.isSaving) {
      return false;
    }
    emit(state.copyWith(isSaving: true, clearError: true));
    try {
      await _completeSession(state.currentAnswers, session);
      return true;
    } on Object catch (error) {
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: 'Sesi tidak dapat diselesaikan: $error',
        ),
      );
      return false;
    }
  }

  Future<bool> cancelSession() async {
    final session = state.session;
    if (session == null ||
        session.status != ExamSessionStatus.active ||
        state.isSaving) {
      return false;
    }
    final now = _utcNow();
    final cancelledSession = session.copyWith(
      status: ExamSessionStatus.cancelled,
      updatedAt: now,
      endedAt: now,
      syncVersion: session.syncVersion + 1,
    );
    emit(state.copyWith(isSaving: true, clearError: true));
    try {
      await _persistenceRepository.endSession(cancelledSession);
      await _trackSafely(
        AnalyticsEvents.practiceCancelled,
        properties: {
          'sessionId': session.id,
          'mode': session.mode.name,
          'answeredCount': state.answeredCount,
          'skippedCount': state.skippedCount,
        },
      );
      emit(
        LearningFlowState(
          answerHistory: state.answerHistory,
          latestScore: state.latestScore,
          profiles: state.profiles,
          recommendation: state.recommendation,
        ),
      );
      return true;
    } on Object catch (error) {
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: 'Sesi tidak dapat dibatalkan: $error',
        ),
      );
      return false;
    }
  }

  bool canViewExplanation(Question question) =>
      _reviewAccessPolicy.canViewExplanation(question);

  Future<void> recordQuestionReviewViewed() async {
    final session = state.session;
    if (state.status != LearningFlowStatus.result || session == null) {
      return;
    }
    await _trackSafely(
      AnalyticsEvents.questionReviewViewed,
      properties: {
        'sessionId': session.id,
        'mode': session.mode.name,
        'questionCount': state.questions.length,
        'skippedCount': state.currentAnswers
            .where((answer) => answer.isSkipped)
            .length,
      },
    );
  }

  Future<void> _trackResponse({
    required ExamSession session,
    required Question question,
    required AnswerRecord answer,
    required AnswerRecord? existing,
  }) async {
    if (answer.isSkipped) {
      if (existing == null || !existing.isSkipped) {
        await _trackSafely(
          AnalyticsEvents.questionSkipped,
          properties: {
            'sessionId': session.id,
            'questionId': question.id,
            'taxonomyNodeId': question.taxonomy.topicId,
            'mode': session.mode.name,
          },
        );
      }
    } else if (existing == null || existing.isSkipped) {
      await _trackSafely(
        AnalyticsEvents.questionAnswered,
        properties: {
          'sessionId': session.id,
          'questionId': question.id,
          'taxonomyNodeId': question.taxonomy.topicId,
          'isCorrect': answer.selectedOptionId == question.correctOptionId,
          'timeSpentMs': answer.timeSpent.inMilliseconds,
        },
      );
    }

    if (existing != null &&
        existing.selectedOptionId != answer.selectedOptionId) {
      await _trackSafely(
        AnalyticsEvents.answerChanged,
        properties: {
          'sessionId': session.id,
          'questionId': question.id,
          'fromOptionId': existing.selectedOptionId ?? 'skipped',
          'toOptionId': answer.selectedOptionId ?? 'skipped',
          'isCorrect': answer.selectedOptionId == question.correctOptionId,
        },
      );
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
    final now = _utcNow();
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
      properties: {
        'sessionId': completedSession.id,
        'score': score.percentage,
        'skippedCount': currentAnswers
            .where((answer) => answer.isSkipped)
            .length,
      },
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

  DateTime _utcNow() => _ensureUtc(_now());

  static DateTime _ensureUtc(DateTime value) =>
      value.isUtc ? value : value.toUtc();

  static AnswerRecord? _answerFor(
    List<AnswerRecord> answers,
    String questionId,
  ) {
    for (final answer in answers) {
      if (answer.questionId == questionId) {
        return answer;
      }
    }
    return null;
  }

  static List<AnswerRecord> _replaceAnswer(
    List<AnswerRecord> answers,
    AnswerRecord answer,
  ) {
    final byId = {for (final item in answers) item.questionId: item};
    byId[answer.questionId] = answer;
    return List.unmodifiable(byId.values);
  }

  static int _nextPendingQuestionIndex(
    int currentIndex,
    List<Question> questions,
    List<AnswerRecord> answers,
  ) {
    final responded = answers.map((answer) => answer.questionId).toSet();
    for (var offset = 1; offset <= questions.length; offset++) {
      final index = (currentIndex + offset) % questions.length;
      if (!responded.contains(questions[index].id)) {
        return index;
      }
    }
    return questions.length;
  }

  static int _recoverQuestionIndex(
    int persistedIndex,
    List<Question> questions,
    List<AnswerRecord> answers,
  ) {
    if (persistedIndex >= 0 && persistedIndex < questions.length) {
      return persistedIndex;
    }
    final responded = answers.map((answer) => answer.questionId).toSet();
    return questions.indexWhere((question) => !responded.contains(question.id));
  }
}
