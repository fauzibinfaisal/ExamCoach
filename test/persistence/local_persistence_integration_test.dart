import 'dart:io';

import 'package:exam_coach/analytics/analytics_events.dart';
import 'package:exam_coach/analytics/local_analytics.dart';
import 'package:exam_coach/features/exam/data/local_question_repository.dart';
import 'package:exam_coach/features/exam/data/mock_question_repository.dart';
import 'package:exam_coach/features/exam/data/question_pack_codec.dart';
import 'package:exam_coach/features/exam/domain/models/question_pack.dart';
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

  test(
    'migrates content, skipped answers, and sync delivery from v1 to v5',
    () async {
      final databasePath = _databasePath(temporaryDirectory);
      final legacyDatabase = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (database, version) async {
            await database.execute(
              'CREATE TABLE legacy_marker (id TEXT PRIMARY KEY)',
            );
            await database.execute(
              'CREATE TABLE question_packs (id TEXT PRIMARY KEY)',
            );
            await database.execute('''
            CREATE TABLE questions (
              id TEXT PRIMARY KEY,
              pack_id TEXT NOT NULL
            )
          ''');
            await database.execute('''
            CREATE TABLE user_answers (
              session_id TEXT NOT NULL,
              question_id TEXT NOT NULL,
              position INTEGER NOT NULL,
              selected_option_id TEXT NOT NULL,
              correct_option_id TEXT NOT NULL,
              is_correct INTEGER NOT NULL,
              time_spent_ms INTEGER NOT NULL,
              changed_answer INTEGER NOT NULL DEFAULT 0,
              answered_at TEXT NOT NULL,
              PRIMARY KEY (session_id, question_id)
            )
          ''');
            await database.insert('question_packs', {
              'id': LocalQuestionRepository.prototypePackId,
            });
            await database.insert('questions', {
              'id': 'q_ratio_01',
              'pack_id': LocalQuestionRepository.prototypePackId,
            });
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

      expect(await opened.getVersion(), ExamCoachDatabase.schemaVersion);
      expect(tableNames, contains('legacy_marker'));
      expect(tableNames, contains('analytics_events'));
      expect(tableNames, contains('sync_outbox'));
      final packColumns = await opened.rawQuery(
        'PRAGMA table_info(question_packs)',
      );
      final questionColumns = await opened.rawQuery(
        'PRAGMA table_info(questions)',
      );
      final answerColumns = await opened.rawQuery(
        'PRAGMA table_info(user_answers)',
      );
      final outboxColumns = await opened.rawQuery(
        'PRAGMA table_info(sync_outbox)',
      );
      expect(
        packColumns.map((column) => column['name']),
        containsAll({
          'title',
          'author',
          'reviewer',
          'generator_provider',
          'generator_model',
          'prompt_version',
          'generated_at',
          'tryout_question_ids_json',
        }),
      );
      expect(
        questionColumns.map((column) => column['name']),
        containsAll({'author', 'reviewer'}),
      );
      expect(
        answerColumns.map((column) => column['name']),
        contains('is_skipped'),
      );
      expect(
        outboxColumns.map((column) => column['name']),
        containsAll({
          'last_attempt_at',
          'next_attempt_at',
          'synced_at',
          'dead_lettered_at',
          'acknowledgement',
          'remote_revision',
        }),
      );
      final migratedPack = await opened.query('question_packs');
      expect(migratedPack.single['author'], 'examcoach_development_team');
      expect(migratedPack.single['title'], 'Diagnostic TIU Prototype');
    },
  );

  test(
    'migrates an existing v4 outbox to retry and acknowledgement fields',
    () async {
      final databasePath = _databasePath(temporaryDirectory);
      final createdAt = DateTime.utc(2026, 9, 5, 12).toIso8601String();
      final legacyDatabase = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (database, version) async {
            await database.execute('''
            CREATE TABLE sync_outbox (
              operation_id TEXT PRIMARY KEY,
              entity_type TEXT NOT NULL,
              entity_id TEXT NOT NULL,
              operation TEXT NOT NULL,
              payload_json TEXT NOT NULL,
              created_at TEXT NOT NULL,
              attempts INTEGER NOT NULL DEFAULT 0,
              status TEXT NOT NULL DEFAULT 'pending',
              last_error TEXT
            )
          ''');
            await database.insert('sync_outbox', {
              'operation_id': 'legacy_synced',
              'entity_type': 'exam_session',
              'entity_id': 'session_legacy',
              'operation': 'complete',
              'payload_json': '{}',
              'created_at': createdAt,
              'attempts': 1,
              'status': SyncOutboxStatus.synced.name,
              'last_error': null,
            });
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
      final columns = await opened.rawQuery('PRAGMA table_info(sync_outbox)');
      final row = (await opened.query('sync_outbox')).single;

      expect(await opened.getVersion(), ExamCoachDatabase.schemaVersion);
      expect(
        columns.map((column) => column['name']),
        containsAll({
          'last_attempt_at',
          'next_attempt_at',
          'synced_at',
          'dead_lettered_at',
          'acknowledgement',
          'remote_revision',
        }),
      );
      expect(row['synced_at'], createdAt);
      expect(row['acknowledgement'], SyncAcknowledgement.accepted.name);
    },
  );

  test('imports and activates a generated draft pack idempotently', () async {
    final generatedPack = const QuestionPackCodec().decode(
      File('content/examples/question_pack.example.json').readAsStringSync(),
    );
    final databasePath = _databasePath(temporaryDirectory);
    var harness = await _openHarness(
      databasePath,
      importedPacks: [generatedPack],
      activePackId: generatedPack.id,
    );

    expect(harness.questions.allQuestions, hasLength(18));
    expect(
      harness.questions.initialTryoutQuestions.map((question) => question.id),
      generatedPack.tryoutQuestionIds,
    );
    final database = await harness.database.instance;
    final storedPack = await database.query(
      'question_packs',
      where: 'id = ?',
      whereArgs: [generatedPack.id],
    );
    expect(storedPack.single['generator_provider'], 'example_provider');
    expect(storedPack.single['prompt_version'], 'ai_question_pack_v1');
    expect(storedPack.single['validation_status'], 'draft');
    expect(storedPack.single['reviewer'], isNull);
    await harness.database.close();

    harness = await _openHarness(
      databasePath,
      importedPacks: [generatedPack],
      activePackId: generatedPack.id,
    );
    addTearDown(harness.database.close);
    expect(harness.questions.allQuestions, hasLength(18));
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
      expect(cubit.state.status, LearningFlowStatus.reviewing);

      await cubit.close();
      await harness.database.close();

      harness = await _openHarness(databasePath);
      cubit = _createCubit(harness);
      await cubit.restore();

      expect(cubit.state.status, LearningFlowStatus.reviewing);
      expect(cubit.state.currentIndex, 6);
      expect(cubit.state.currentAnswers, hasLength(6));
      expect(await cubit.completeCurrentSession(), isTrue);
      expect(cubit.state.status, LearningFlowStatus.result);

      final pending = await harness.persistence.getPending();
      expect(pending, hasLength(8));
      expect(pending.map((item) => item.operationId).toSet(), hasLength(8));

      final firstOperation = pending.first;
      final attemptedAt = DateTime.utc(2026, 9, 6, 9);
      final nextAttemptAt = attemptedAt.add(const Duration(seconds: 5));
      await harness.persistence.markAttemptFailed(
        firstOperation.operationId,
        'offline',
        attemptedAt: attemptedAt,
        nextAttemptAt: nextAttemptAt,
        deadLetter: false,
      );
      final failedOperation = (await harness.persistence.getPending())
          .firstWhere((item) => item.operationId == firstOperation.operationId);
      expect(failedOperation.attempts, 1);
      expect(failedOperation.lastError, 'offline');
      expect(failedOperation.lastAttemptAt, attemptedAt);
      expect(failedOperation.nextAttemptAt, nextAttemptAt);
      expect(
        (await harness.persistence.getReady(
          now: attemptedAt,
        )).map((item) => item.operationId),
        isNot(contains(firstOperation.operationId)),
      );
      expect(
        (await harness.persistence.getReady(
          now: nextAttemptAt,
        )).map((item) => item.operationId),
        contains(firstOperation.operationId),
      );
      await harness.persistence.markSynced(
        firstOperation.operationId,
        syncedAt: nextAttemptAt,
        acknowledgement: SyncAcknowledgement.accepted,
        remoteRevision: 7,
      );
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

  test('expires an inactive session durably after 24 hours', () async {
    final databasePath = _databasePath(temporaryDirectory);
    var currentTime = DateTime.utc(2026, 9, 6, 8);
    final analytics = InMemoryAnalytics();
    var harness = await _openHarness(databasePath);
    var cubit = _createCubit(
      harness,
      now: () => currentTime,
      analytics: analytics,
    );

    await cubit.startTryout();
    await cubit.skipCurrentQuestion(timeSpent: const Duration(seconds: 4));
    final sessionId = cubit.state.session!.id;
    await cubit.close();
    await harness.database.close();

    currentTime = currentTime.add(const Duration(hours: 25));
    harness = await _openHarness(databasePath);
    cubit = _createCubit(harness, now: () => currentTime, analytics: analytics);
    addTearDown(cubit.close);
    addTearDown(harness.database.close);
    await cubit.restore();

    expect(cubit.state.status, LearningFlowStatus.idle);
    expect(cubit.state.hasActiveSession, isFalse);
    expect(cubit.state.answerHistory, isEmpty);
    expect(cubit.state.errorMessage, contains('kedaluwarsa'));

    final database = await harness.database.instance;
    final sessionRows = await database.query(
      'exam_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    expect(sessionRows.single['status'], 'expired');
    expect(sessionRows.single['ended_at'], isNotNull);
    expect(
      (await harness.persistence.getPending()).map((item) => item.operationId),
      contains('$sessionId:expired'),
    );
    expect(
      analytics.events.map((event) => event.name),
      contains(AnalyticsEvents.practiceExpired),
    );
  });

  test(
    'cancels a partial session without adding it to learning history',
    () async {
      final harness = await _openHarness(_databasePath(temporaryDirectory));
      final analytics = InMemoryAnalytics();
      final cubit = _createCubit(harness, analytics: analytics);
      addTearDown(cubit.close);
      addTearDown(harness.database.close);

      await cubit.startTryout();
      await cubit.skipCurrentQuestion(timeSpent: const Duration(seconds: 3));
      final sessionId = cubit.state.session!.id;
      expect(await cubit.cancelSession(), isTrue);

      final database = await harness.database.instance;
      final sessionRows = await database.query(
        'exam_sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
      );
      final answerRows = await database.query(
        'user_answers',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      final snapshot = await harness.persistence.loadSnapshot();

      expect(sessionRows.single['status'], 'cancelled');
      expect(sessionRows.single['ended_at'], isNotNull);
      expect(answerRows.single['is_skipped'], 1);
      expect(snapshot.activeSession, isNull);
      expect(snapshot.answerHistory, isEmpty);
      expect(
        (await harness.persistence.getPending()).map(
          (item) => item.operationId,
        ),
        contains('$sessionId:cancelled'),
      );
      expect(
        analytics.events.map((event) => event.name),
        contains(AnalyticsEvents.practiceCancelled),
      );
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
    await harness.persistence.markSynced(
      analyticsOperation.operationId,
      syncedAt: DateTime.utc(2026, 9, 6, 10),
      acknowledgement: SyncAcknowledgement.accepted,
      remoteRevision: 1,
    );
    final uploadedEvents = await database.query('analytics_events');
    expect(uploadedEvents.single['upload_status'], 'synced');
  });
}

String _databasePath(Directory directory) =>
    path_util.join(directory.path, 'exam_coach_test.sqlite');

Future<_PersistenceHarness> _openHarness(
  String databasePath, {
  List<QuestionPack> importedPacks = const [],
  String activePackId = LocalQuestionRepository.prototypePackId,
}) async {
  final database = ExamCoachDatabase(
    databasePath: databasePath,
    factory: databaseFactoryFfi,
  );
  await database.instance;
  final questions = LocalQuestionRepository(database);
  await questions.initializeWithSeed(
    MockQuestionRepository(),
    importedPacks: importedPacks,
    activePackId: activePackId,
  );
  return _PersistenceHarness(
    database: database,
    questions: questions,
    persistence: LocalLearningPersistenceRepository(database),
  );
}

LearningFlowCubit _createCubit(
  _PersistenceHarness harness, {
  UtcNow? now,
  AnalyticsTracker? analytics,
}) {
  return LearningFlowCubit(
    questionRepository: harness.questions,
    scoringEngine: const ScoringEngine(),
    weaknessAnalyzer: const WeaknessAnalyzer(),
    recommendationEngine: const RecommendationEngine(),
    adaptiveDrillEngine: const AdaptiveDrillEngine(),
    persistenceRepository: harness.persistence,
    analytics: analytics ?? InMemoryAnalytics(),
    now: now,
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
