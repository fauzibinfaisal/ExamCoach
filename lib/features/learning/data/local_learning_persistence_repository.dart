import 'dart:convert';

import 'package:exam_coach/features/exam/domain/models/answer_record.dart';
import 'package:exam_coach/features/exam/domain/models/exam_session.dart';
import 'package:exam_coach/features/learning/domain/models/learning_persistence_snapshot.dart';
import 'package:exam_coach/features/learning/domain/repositories/learning_persistence_repository.dart';
import 'package:exam_coach/learning_engine/models/recommendation.dart';
import 'package:exam_coach/learning_engine/models/score_result.dart';
import 'package:exam_coach/learning_engine/models/weakness_profile.dart';
import 'package:exam_coach/services/database/exam_coach_database.dart';
import 'package:exam_coach/services/sync/domain/sync_outbox_item.dart';
import 'package:exam_coach/services/sync/domain/sync_outbox_repository.dart';
import 'package:sqflite/sqflite.dart';

class LocalLearningPersistenceRepository
    implements LearningPersistenceRepository, SyncOutboxRepository {
  LocalLearningPersistenceRepository(this._database);

  final ExamCoachDatabase _database;

  @override
  Future<LearningPersistenceSnapshot> loadSnapshot() async {
    final database = await _database.instance;
    final activeRows = await database.query(
      'exam_sessions',
      where: 'status = ?',
      whereArgs: [ExamSessionStatus.active.name],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    final activeSession = activeRows.isEmpty
        ? null
        : _sessionFromRow(activeRows.first);
    final activeAnswers = activeSession == null
        ? const <AnswerRecord>[]
        : await _answersForSession(database, activeSession.id);

    final historyRows = await database.rawQuery(
      '''
      SELECT answer.*
      FROM user_answers AS answer
      INNER JOIN exam_sessions AS session ON session.id = answer.session_id
      WHERE session.status = ?
      ORDER BY answer.answered_at ASC
    ''',
      [ExamSessionStatus.completed.name],
    );
    final answerHistory = List<AnswerRecord>.unmodifiable(
      historyRows.map(_answerFromRow),
    );

    final completedRows = await database.query(
      'exam_sessions',
      where: 'status = ?',
      whereArgs: [ExamSessionStatus.completed.name],
      orderBy: 'ended_at DESC',
      limit: 1,
    );
    ScoreResult? latestScore;
    if (completedRows.isNotEmpty) {
      final sessionId = completedRows.first['id']! as String;
      final rows = await database.query(
        'user_answers',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'position ASC',
      );
      latestScore = ScoreResult(
        evaluations: List.unmodifiable(rows.map(_evaluationFromRow)),
      );
    }

    final profileRows = await database.query(
      'weakness_profiles',
      orderBy: 'weakness_score DESC',
    );
    final recommendationRows = await database.query(
      'recommendations',
      orderBy: 'generated_at DESC',
      limit: 1,
    );

    return LearningPersistenceSnapshot(
      activeSession: activeSession,
      activeAnswers: List.unmodifiable(activeAnswers),
      answerHistory: answerHistory,
      latestScore: latestScore,
      profiles: List.unmodifiable(profileRows.map(_profileFromRow)),
      recommendation: recommendationRows.isEmpty
          ? null
          : _recommendationFromRow(recommendationRows.first),
    );
  }

  @override
  Future<void> startSession(ExamSession session) async {
    final database = await _database.instance;
    await database.transaction((transaction) async {
      await transaction.update(
        'exam_sessions',
        {
          'status': ExamSessionStatus.cancelled.name,
          'ended_at': session.startedAt.toIso8601String(),
          'updated_at': session.startedAt.toIso8601String(),
        },
        where: 'status = ?',
        whereArgs: [ExamSessionStatus.active.name],
      );
      await transaction.insert('exam_sessions', _sessionToRow(session));
      await _insertOutbox(
        transaction,
        operationId: '${session.id}:start',
        entityType: 'exam_session',
        entityId: session.id,
        operation: 'upsert',
        payload: _sessionToRow(session),
        createdAt: session.startedAt,
      );
    });
  }

  @override
  Future<void> saveAnswer({
    required ExamSession session,
    required AnswerRecord answer,
    required String correctOptionId,
    required bool isCorrect,
  }) async {
    final database = await _database.instance;
    final answerRow = <String, Object?>{
      'session_id': session.id,
      'question_id': answer.questionId,
      'position': session.currentIndex - 1,
      'selected_option_id': answer.selectedOptionId,
      'correct_option_id': correctOptionId,
      'is_correct': isCorrect ? 1 : 0,
      'time_spent_ms': answer.timeSpent.inMilliseconds,
      'changed_answer': answer.changedAnswer ? 1 : 0,
      'answered_at': answer.answeredAt.toIso8601String(),
    };
    await database.transaction((transaction) async {
      final updated = await transaction.update(
        'exam_sessions',
        {
          'current_index': session.currentIndex,
          'updated_at': session.updatedAt.toIso8601String(),
          'sync_version': session.syncVersion,
        },
        where: 'id = ? AND status = ?',
        whereArgs: [session.id, ExamSessionStatus.active.name],
      );
      if (updated != 1) {
        throw StateError('Cannot update inactive session ${session.id}.');
      }
      await transaction.insert(
        'user_answers',
        answerRow,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _insertOutbox(
        transaction,
        operationId: '${session.id}:answer:${answer.questionId}',
        entityType: 'user_answer',
        entityId: '${session.id}:${answer.questionId}',
        operation: 'upsert',
        payload: answerRow,
        createdAt: answer.answeredAt,
      );
    });
  }

  @override
  Future<void> completeSession({
    required ExamSession session,
    required ScoreResult score,
    required List<WeaknessProfile> profiles,
    required LearningRecommendation? recommendation,
  }) async {
    final database = await _database.instance;
    await database.transaction((transaction) async {
      final updated = await transaction.update(
        'exam_sessions',
        _sessionToRow(session),
        where: 'id = ?',
        whereArgs: [session.id],
      );
      if (updated != 1) {
        throw StateError('Cannot complete missing session ${session.id}.');
      }

      for (final profile in profiles) {
        await transaction.insert(
          'weakness_profiles',
          _profileToRow(profile, session.updatedAt),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (recommendation != null) {
        await transaction.insert(
          'recommendations',
          _recommendationToRow(
            recommendation,
            sessionId: session.id,
            generatedAt: session.updatedAt,
          ),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await _insertOutbox(
        transaction,
        operationId: '${session.id}:complete',
        entityType: 'exam_session',
        entityId: session.id,
        operation: 'complete',
        payload: {
          ..._sessionToRow(session),
          'correct_answers': score.correct,
          'total_answers': score.total,
        },
        createdAt: session.updatedAt,
      );
    });
  }

  @override
  Future<List<SyncOutboxItem>> getPending({int limit = 50}) async {
    final database = await _database.instance;
    final rows = await database.query(
      'sync_outbox',
      where: 'status = ?',
      whereArgs: [SyncOutboxStatus.pending.name],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return List.unmodifiable(rows.map(_outboxFromRow));
  }

  @override
  Future<void> markAttemptFailed(String operationId, String error) async {
    final database = await _database.instance;
    await database.rawUpdate(
      '''
      UPDATE sync_outbox
      SET attempts = attempts + 1, last_error = ?, status = ?
      WHERE operation_id = ?
    ''',
      [error, SyncOutboxStatus.pending.name, operationId],
    );
  }

  @override
  Future<void> markSynced(String operationId) async {
    final database = await _database.instance;
    await database.transaction((transaction) async {
      final rows = await transaction.query(
        'sync_outbox',
        columns: const ['entity_type', 'entity_id'],
        where: 'operation_id = ?',
        whereArgs: [operationId],
        limit: 1,
      );
      if (rows.isEmpty) {
        return;
      }
      await transaction.update(
        'sync_outbox',
        {'status': SyncOutboxStatus.synced.name, 'last_error': null},
        where: 'operation_id = ?',
        whereArgs: [operationId],
      );
      if (rows.first['entity_type'] == 'analytics_event') {
        await transaction.update(
          'analytics_events',
          {'upload_status': SyncOutboxStatus.synced.name},
          where: 'id = ?',
          whereArgs: [rows.first['entity_id']],
        );
      }
    });
  }

  static Future<List<AnswerRecord>> _answersForSession(
    Database database,
    String sessionId,
  ) async {
    final rows = await database.query(
      'user_answers',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'position ASC',
    );
    return rows.map(_answerFromRow).toList(growable: false);
  }

  static Map<String, Object?> _sessionToRow(ExamSession session) => {
    'id': session.id,
    'user_id': session.userId,
    'test_id': session.testId,
    'mode': session.mode.name,
    'status': session.status.name,
    'question_ids_json': jsonEncode(session.questionIds),
    'current_index': session.currentIndex,
    'started_at': session.startedAt.toIso8601String(),
    'updated_at': session.updatedAt.toIso8601String(),
    'ended_at': session.endedAt?.toIso8601String(),
    'score': session.score,
    'sync_version': session.syncVersion,
  };

  static ExamSession _sessionFromRow(Map<String, Object?> row) {
    final questionIds =
        (jsonDecode(row['question_ids_json']! as String) as List)
            .cast<String>();
    return ExamSession(
      id: row['id']! as String,
      userId: row['user_id']! as String,
      testId: row['test_id']! as String,
      mode: ExamSessionMode.values.byName(row['mode']! as String),
      status: ExamSessionStatus.values.byName(row['status']! as String),
      questionIds: List.unmodifiable(questionIds),
      currentIndex: row['current_index']! as int,
      startedAt: DateTime.parse(row['started_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
      endedAt: row['ended_at'] == null
          ? null
          : DateTime.parse(row['ended_at']! as String),
      score: row['score'] as int?,
      syncVersion: row['sync_version']! as int,
    );
  }

  static AnswerRecord _answerFromRow(Map<String, Object?> row) => AnswerRecord(
    questionId: row['question_id']! as String,
    selectedOptionId: row['selected_option_id']! as String,
    timeSpent: Duration(milliseconds: row['time_spent_ms']! as int),
    answeredAt: DateTime.parse(row['answered_at']! as String),
    changedAnswer: row['changed_answer'] == 1,
  );

  static AnswerEvaluation _evaluationFromRow(Map<String, Object?> row) =>
      AnswerEvaluation(
        questionId: row['question_id']! as String,
        selectedOptionId: row['selected_option_id']! as String,
        correctOptionId: row['correct_option_id']! as String,
        isCorrect: row['is_correct'] == 1,
      );

  static Map<String, Object?> _profileToRow(
    WeaknessProfile profile,
    DateTime updatedAt,
  ) => {
    'taxonomy_node_id': profile.taxonomyNodeId,
    'taxonomy_label': profile.taxonomyLabel,
    'weakness_score': profile.weaknessScore,
    'confidence': profile.confidence,
    'sample_size': profile.sampleSize,
    'trend': profile.trend.name,
    'tier': profile.tier.name,
    'evidence_json': jsonEncode(profile.evidence),
    'algorithm_version': profile.algorithmVersion,
    'updated_at': updatedAt.toIso8601String(),
  };

  static WeaknessProfile _profileFromRow(Map<String, Object?> row) =>
      WeaknessProfile(
        taxonomyNodeId: row['taxonomy_node_id']! as String,
        taxonomyLabel: row['taxonomy_label']! as String,
        weaknessScore: (row['weakness_score']! as num).toDouble(),
        confidence: (row['confidence']! as num).toDouble(),
        sampleSize: row['sample_size']! as int,
        trend: PerformanceTrend.values.byName(row['trend']! as String),
        tier: WeaknessTier.values.byName(row['tier']! as String),
        evidence: List.unmodifiable(
          (jsonDecode(row['evidence_json']! as String) as List).cast<String>(),
        ),
        algorithmVersion: row['algorithm_version']! as String,
      );

  static Map<String, Object?> _recommendationToRow(
    LearningRecommendation recommendation, {
    required String sessionId,
    required DateTime generatedAt,
  }) => {
    'id': 'recommendation_$sessionId',
    'session_id': sessionId,
    'recommendation_type': recommendation.type.name,
    'target_taxonomy_id': recommendation.targetTaxonomyId,
    'target_label': recommendation.targetLabel,
    'priority': recommendation.priority,
    'reason_code': recommendation.reasonCode.name,
    'reason': recommendation.reason,
    'expected_benefit': recommendation.expectedBenefit,
    'estimated_effort_ms': recommendation.estimatedEffort.inMilliseconds,
    'confidence': recommendation.confidence,
    'algorithm_version': recommendation.algorithmVersion,
    'generated_at': generatedAt.toIso8601String(),
    'expires_at': null,
  };

  static LearningRecommendation _recommendationFromRow(
    Map<String, Object?> row,
  ) => LearningRecommendation(
    type: RecommendationType.values.byName(
      row['recommendation_type']! as String,
    ),
    targetTaxonomyId: row['target_taxonomy_id']! as String,
    targetLabel: row['target_label']! as String,
    priority: row['priority']! as int,
    reasonCode: RecommendationReasonCode.values.byName(
      row['reason_code']! as String,
    ),
    reason: row['reason']! as String,
    expectedBenefit: row['expected_benefit']! as String,
    estimatedEffort: Duration(milliseconds: row['estimated_effort_ms']! as int),
    confidence: (row['confidence']! as num).toDouble(),
    algorithmVersion: row['algorithm_version']! as String,
  );

  static Future<void> _insertOutbox(
    DatabaseExecutor executor, {
    required String operationId,
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, Object?> payload,
    required DateTime createdAt,
  }) async {
    await executor.insert('sync_outbox', {
      'operation_id': operationId,
      'entity_type': entityType,
      'entity_id': entityId,
      'operation': operation,
      'payload_json': jsonEncode(payload),
      'created_at': createdAt.toIso8601String(),
      'attempts': 0,
      'status': SyncOutboxStatus.pending.name,
      'last_error': null,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static SyncOutboxItem _outboxFromRow(Map<String, Object?> row) {
    final payload = jsonDecode(row['payload_json']! as String);
    return SyncOutboxItem(
      operationId: row['operation_id']! as String,
      entityType: row['entity_type']! as String,
      entityId: row['entity_id']! as String,
      operation: row['operation']! as String,
      payload: Map<String, Object?>.from(payload as Map),
      createdAt: DateTime.parse(row['created_at']! as String),
      attempts: row['attempts']! as int,
      status: SyncOutboxStatus.values.byName(row['status']! as String),
      lastError: row['last_error'] as String?,
    );
  }
}
