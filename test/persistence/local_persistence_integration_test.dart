import 'dart:io';

import 'package:exam_coach/analytics/analytics_events.dart';
import 'package:exam_coach/analytics/local_analytics.dart';
import 'package:exam_coach/features/exam/data/local_question_repository.dart';
import 'package:exam_coach/features/exam/data/mock_question_repository.dart';
import 'package:exam_coach/features/learning/application/learning_flow_cubit.dart';
import 'package:exam_coach/features/learning/application/learning_flow_state.dart';
import 'package:exam_coach/features/learning/data/local_learning_persistence_repository.dart';
import 'package:exam_coach/learning_engine/adaptive_drill_engine.dart';
import 'package:exam_coach/learning_engine/recommendation_engine.dart';
import 'package:exam_coach/learning_engine/scoring_engine.dart';
import 'package:exam_coach/learning_engine/weakness_analyzer.dart';
import 'package:exam_coach/services/database/exam_coach_database.dart';
import 'package:exam_coach/services/sync/domain/sync_outbox_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path_util;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'exam_coach_persistence_test_',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('creates the versioned schema and persists the question pack', () async {
    final harness = await _openHarness(_databasePath(temporaryDirectory));
    addTearDown(harness.database.close);

    final database = await harness.database.instance;
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final tableNames = tables.map((row) => row['name']).toSet();

    expect(await database.getVersion(), ExamCoachDatabase.schemaVersion);
    expect(
      tableNames,
      containsAll({
        'question_packs',
        'questions',
        'exam_sessions',
        'user_answers',
        'weakness_profiles',
        'recommendations',
        'analytics_events',
        'sync_outbox',
      }),
    );
    expect(harness.questions.allQuestions, hasLength(12));
    expect(harness.questions.initialTryoutQuestions, hasLength(6));
    expect(
      harness.questions.allQuestions.every(
        (question) => question.validationStatus.name == 'draft',
      ),
      isTrue,
    );
  });

  test('migrates telemetry and outbox tables from schema v1 to v2', () async {
    final databasePath = _databasePath(temporaryDirectory);
    final legacyDatabase = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
          await database.execute(
            'CREATE TABLE legacy_marker (id TEXT PRIMARY KEY)',
          );
        },
      ),
    );
    await legacyDatabase.close();

    final database = ExamCoachDatabase(
      databasePath: databasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(database.close);
    final opened = await database.instance;
    final tables = await opened.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final tableNames = tables.map((row) => row['name']).toSet();

    expect(await opened.getVersion(), 2);
    expect(tableNames, contains('legacy_marker'));
    expect(tableNames, contains('analytics_events'));
    expect(tableNames, contains('sync_outbox'));
  });

  test(
    'recovers an interrupted session and completed learning history',
    () async {
      final databasePath = _databasePath(temporaryDirectory);
      var harness = await _openHarness(databasePath);
      var cubit = _createCubit(harness);

      expect(await cubit.startTryout(), isTrue);
      cubit.selectOption('a');
      await cubit.submitCurrentAnswer(timeSpent: const Duration(seconds: 20));

      final session = cubit.state.session!;
      final firstQuestion = cubit.state.questions.first;
      final firstAnswer = cubit.state.currentAnswers.first;
      final beforeDuplicate = await harness.persistence.getPending();
      await harness.persistence.saveAnswer(
        session: session,
        answer: firstAnswer,
        correctOptionId: firstQuestion.correctOptionId,
        isCorrect:
            firstAnswer.selectedOptionId == firstQuestion.correctOptionId,
      );
      final afterDuplicate = await harness.persistence.getPending();
      expect(afterDuplicate, hasLength(beforeDuplicate.length));

      cubit.selectOption('a');
      await cubit.submitCurrentAnswer(timeSpent: const Duration(seconds: 25));
      expect(cubit.state.currentIndex, 2);
      expect(cubit.state.currentAnswers, hasLength(2));

      await cubit.close();
      await harness.database.close();

      harness = await _openHarness(databasePath);
      cubit = _createCubit(harness);
      await cubit.restore();

      expect(cubit.state.status, LearningFlowStatus.answering);
      expect(cubit.state.currentIndex, 2);
      expect(cubit.state.currentAnswers, hasLength(2));
      expect(cubit.state.currentQuestion?.id, 'q_sequence_01');
      expect(cubit.state.answerHistory, isEmpty);

      for (var index = 2; index < 6; index++) {
        cubit.selectOption('a');
        await cubit.submitCurrentAnswer(timeSpent: const Duration(seconds: 30));
      }
      expect(cubit.state.status, LearningFlowStatus.result);

      final pending = await harness.persistence.getPending();
      expect(pending, hasLength(8));
      expect(pending.map((item) => item.operationId).toSet(), hasLength(8));

      final firstOperation = pending.first;
      await harness.persistence.markAttemptFailed(
        firstOperation.operationId,
        'offline',
      );
      final failedOperation = (await harness.persistence.getPending())
          .firstWhere((item) => item.operationId == firstOperation.operationId);
      expect(failedOperation.attempts, 1);
      expect(failedOperation.lastError, 'offline');
      await harness.persistence.markSynced(firstOperation.operationId);
      expect(
        (await harness.persistence.getPending()).map(
          (item) => item.operationId,
        ),
        isNot(contains(firstOperation.operationId)),
      );

      await cubit.close();
      await harness.database.close();

      harness = await _openHarness(databasePath);
      cubit = _createCubit(harness);
      addTearDown(cubit.close);
      addTearDown(harness.database.close);
      await cubit.restore();

      expect(cubit.state.status, LearningFlowStatus.idle);
      expect(cubit.state.hasActiveSession, isFalse);
      expect(cubit.state.answerHistory, hasLength(6));
      expect(cubit.state.latestScore, isNotNull);
      expect(cubit.state.profiles, hasLength(3));
      expect(cubit.state.recommendation, isNotNull);
      expect(await harness.persistence.getPending(), hasLength(7));
    },
  );

  test('stores analytics durably and queues each event for sync', () async {
    final databasePath = _databasePath(temporaryDirectory);
    var harness = await _openHarness(databasePath);
    final analytics = LocalAnalytics(harness.database);
    await analytics.track(
      AnalyticsEvents.questionAnswered,
      properties: const {
        'sessionId': 'session_test',
        'questionId': 'q_test',
        'isCorrect': true,
      },
    );
    await harness.database.close();

    harness = await _openHarness(databasePath);
    addTearDown(harness.database.close);
    final database = await harness.database.instance;
    final events = await database.query('analytics_events');
    final outbox = await harness.persistence.getPending();

    expect(events, hasLength(1));
    expect(events.single['event_name'], AnalyticsEvents.questionAnswered);
    expect(
      outbox.where(
        (item) =>
            item.entityType == 'analytics_event' &&
            item.status == SyncOutboxStatus.pending,
      ),
      hasLength(1),
    );

    final analyticsOperation = outbox.singleWhere(
      (item) => item.entityType == 'analytics_event',
    );
    await harness.persistence.markSynced(analyticsOperation.operationId);
    final uploadedEvents = await database.query('analytics_events');
    expect(uploadedEvents.single['upload_status'], 'synced');
  });
}

String _databasePath(Directory directory) =>
    path_util.join(directory.path, 'exam_coach_test.sqlite');

Future<_PersistenceHarness> _openHarness(String databasePath) async {
  final database = ExamCoachDatabase(
    databasePath: databasePath,
    factory: databaseFactoryFfi,
  );
  await database.instance;
  final questions = LocalQuestionRepository(database);
  await questions.initializeWithSeed(MockQuestionRepository());
  return _PersistenceHarness(
    database: database,
    questions: questions,
    persistence: LocalLearningPersistenceRepository(database),
  );
}

LearningFlowCubit _createCubit(_PersistenceHarness harness) {
  return LearningFlowCubit(
    questionRepository: harness.questions,
    scoringEngine: const ScoringEngine(),
    weaknessAnalyzer: const WeaknessAnalyzer(),
    recommendationEngine: const RecommendationEngine(),
    adaptiveDrillEngine: const AdaptiveDrillEngine(),
    persistenceRepository: harness.persistence,
    analytics: InMemoryAnalytics(),
  );
}

class _PersistenceHarness {
  const _PersistenceHarness({
    required this.database,
    required this.questions,
    required this.persistence,
  });

  final ExamCoachDatabase database;
  final LocalQuestionRepository questions;
  final LocalLearningPersistenceRepository persistence;
}
