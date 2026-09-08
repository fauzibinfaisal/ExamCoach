import 'dart:convert';
import 'dart:io';

import 'package:exam_coach/analytics/analytics_events.dart';
import 'package:exam_coach/analytics/local_analytics.dart';
import 'package:exam_coach/features/auth/data/local_account_data_store.dart';
import 'package:exam_coach/features/auth/domain/account_data_store.dart';
import 'package:exam_coach/features/auth/domain/user_identity.dart';
import 'package:exam_coach/features/exam/data/local_question_repository.dart';
import 'package:exam_coach/features/exam/data/mock_question_repository.dart';
import 'package:exam_coach/features/exam/domain/models/exam_session.dart';
import 'package:exam_coach/features/learning/application/learning_flow_cubit.dart';
import 'package:exam_coach/features/learning/data/local_learning_persistence_repository.dart';
import 'package:exam_coach/learning_engine/adaptive_drill_engine.dart';
import 'package:exam_coach/learning_engine/recommendation_engine.dart';
import 'package:exam_coach/learning_engine/scoring_engine.dart';
import 'package:exam_coach/learning_engine/weakness_analyzer.dart';
import 'package:exam_coach/services/database/exam_coach_database.dart';
import 'package:exam_coach/services/sync/domain/remote_learning_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path_util;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'exam_coach_account_test_',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'atomically claims local learning, analytics, and outbox ownership',
    () async {
      final harness = await _openHarness(temporaryDirectory);
      addTearDown(harness.database.close);
      final identity = UserIdentity();
      final cubit = _learningCubit(harness, identity);
      addTearDown(cubit.close);
      expect(await cubit.startTryout(), isTrue);
      await LocalAnalytics(
        harness.database,
        userIdentity: identity,
      ).track(AnalyticsEvents.resultViewed);

      final claim = await harness.accounts.claimForUser(
        'firebase_user_123',
        claimedAt: DateTime.utc(2026, 9, 7, 8),
      );
      final database = await harness.database.instance;
      final outbox = await database.query('sync_outbox');
      final payloadOwners = outbox
          .map((row) => jsonDecode(row['payload_json']! as String))
          .whereType<Map<String, dynamic>>()
          .map((payload) => payload['user_id'])
          .whereType<String>();

      expect(claim.newBinding, isTrue);
      expect(claim.claimedLocalData, isTrue);
      expect(await harness.accounts.loadBoundUserId(), 'firebase_user_123');
      expect(
        (await database.query('exam_sessions')).single['user_id'],
        'firebase_user_123',
      );
      expect(
        (await database.query('analytics_events')).single['user_id'],
        'firebase_user_123',
      );
      expect(payloadOwners, everyElement('firebase_user_123'));

      final repeated = await harness.accounts.claimForUser(
        'firebase_user_123',
        claimedAt: DateTime.utc(2026, 9, 7, 9),
      );
      expect(repeated.newBinding, isFalse);
      await expectLater(
        harness.accounts.claimForUser(
          'different_user',
          claimedAt: DateTime.utc(2026, 9, 7, 10),
        ),
        throwsA(isA<AccountBindingConflict>()),
      );
    },
  );

  test(
    'imports an owned empty-device recovery and recomputes its score',
    () async {
      final harness = await _openHarness(temporaryDirectory);
      addTearDown(harness.database.close);
      const userId = 'firebase_user_123';
      await harness.accounts.claimForUser(
        userId,
        claimedAt: DateTime.utc(2026, 9, 7, 8),
      );
      final questions = harness.questions.initialTryoutQuestions
          .take(2)
          .toList();
      final startedAt = DateTime.utc(2026, 9, 6, 8);
      final endedAt = DateTime.utc(2026, 9, 6, 8, 2);
      final session = ExamSession(
        id: 'remote_session_1',
        userId: userId,
        testId: questions.first.taxonomy.testId,
        mode: ExamSessionMode.tryout,
        status: ExamSessionStatus.completed,
        questionIds: questions.map((question) => question.id).toList(),
        currentIndex: 2,
        startedAt: startedAt,
        updatedAt: endedAt,
        endedAt: endedAt,
        // Deliberately untrusted. Import must recompute this from local content.
        score: 100,
        syncVersion: 4,
      );
      final result = await harness.accounts.importRecoverySnapshot(
        RemoteLearningSnapshot(
          userId: userId,
          remoteRevision: 12,
          sessions: [session],
          answers: [
            RemoteAnswerRecord(
              sessionId: session.id,
              questionId: questions.first.id,
              position: 0,
              selectedOptionId: questions.first.correctOptionId,
              timeSpent: const Duration(seconds: 30),
              changedAnswer: false,
              answeredAt: startedAt.add(const Duration(seconds: 30)),
            ),
            RemoteAnswerRecord(
              sessionId: session.id,
              questionId: questions.last.id,
              position: 1,
              selectedOptionId: null,
              timeSpent: const Duration(seconds: 25),
              changedAnswer: false,
              answeredAt: startedAt.add(const Duration(seconds: 55)),
            ),
          ],
        ),
        recoveredAt: DateTime.utc(2026, 9, 7, 8, 5),
      );
      final database = await harness.database.instance;
      final storedSession = (await database.query('exam_sessions')).single;
      final storedAnswers = await database.query(
        'user_answers',
        orderBy: 'position ASC',
      );
      final binding = (await database.query('account_binding')).single;

      expect(result.status, RecoveryImportStatus.imported);
      expect(result.sessionCount, 1);
      expect(result.answerCount, 2);
      expect(storedSession['score'], 50);
      expect(
        storedAnswers.first['correct_option_id'],
        questions.first.correctOptionId,
      );
      expect(storedAnswers.first['is_correct'], 1);
      expect(storedAnswers.last['is_skipped'], 1);
      expect(binding['remote_revision'], 12);
      expect(binding['last_recovered_at'], isNotNull);
    },
  );

  test(
    'preserves existing local sessions instead of applying remote state',
    () async {
      final harness = await _openHarness(temporaryDirectory);
      addTearDown(harness.database.close);
      final identity = UserIdentity();
      final cubit = _learningCubit(harness, identity);
      addTearDown(cubit.close);
      expect(await cubit.startTryout(), isTrue);
      await harness.accounts.claimForUser(
        'firebase_user_123',
        claimedAt: DateTime.utc(2026, 9, 7, 8),
      );

      final result = await harness.accounts.importRecoverySnapshot(
        RemoteLearningSnapshot(
          userId: 'firebase_user_123',
          remoteRevision: 99,
          sessions: const [],
          answers: const [],
        ),
        recoveredAt: DateTime.utc(2026, 9, 7, 8, 5),
      );
      final database = await harness.database.instance;

      expect(result.status, RecoveryImportStatus.skippedLocalData);
      expect(await database.query('exam_sessions'), hasLength(1));
      expect(
        (await database.query('account_binding')).single['remote_revision'],
        0,
      );
    },
  );
}

Future<_AccountHarness> _openHarness(Directory directory) async {
  final database = ExamCoachDatabase(
    databasePath: path_util.join(directory.path, 'account_test.sqlite'),
    factory: databaseFactoryFfi,
  );
  await database.instance;
  final questions = LocalQuestionRepository(database);
  await questions.initializeWithSeed(MockQuestionRepository());
  return _AccountHarness(
    database: database,
    questions: questions,
    persistence: LocalLearningPersistenceRepository(database),
    accounts: LocalAccountDataStore(database),
  );
}

LearningFlowCubit _learningCubit(
  _AccountHarness harness,
  UserIdentity identity,
) => LearningFlowCubit(
  questionRepository: harness.questions,
  scoringEngine: const ScoringEngine(),
  weaknessAnalyzer: const WeaknessAnalyzer(),
  recommendationEngine: const RecommendationEngine(),
  adaptiveDrillEngine: const AdaptiveDrillEngine(),
  persistenceRepository: harness.persistence,
  userIdentity: identity,
);

class _AccountHarness {
  const _AccountHarness({
    required this.database,
    required this.questions,
    required this.persistence,
    required this.accounts,
  });

  final ExamCoachDatabase database;
  final LocalQuestionRepository questions;
  final LocalLearningPersistenceRepository persistence;
  final LocalAccountDataStore accounts;
}
