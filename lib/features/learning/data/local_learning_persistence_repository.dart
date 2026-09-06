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
    final position = session.questionIds.indexOf(answer.questionId);
    if (position < 0) {
      throw StateError(
        'Question ${answer.questionId} does not belong to session ${session.id}.',
      );
    }
    final answerRow = <String, Object?>{
      'session_id': session.id,
      'question_id': answer.questionId,
      'position': position,
      'selected_option_id': answer.selectedOptionId ?? '',
      'correct_option_id': correctOptionId,
      'is_correct': isCorrect ? 1 : 0,
      'is_skipped': answer.isSkipped ? 1 : 0,
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
        replaceExisting: true,
      );
    });
  }

  @override
  Future<void> updateSessionCursor(ExamSession session) async {
    final database = await _database.instance;
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
        throw StateError('Cannot move inactive session ${session.id}.');
      }
      await _insertOutbox(
        transaction,
        operationId: '${session.id}:progress',
        entityType: 'exam_session',
        entityId: session.id,
        operation: 'progress',
        payload: _sessionToRow(session),
        createdAt: session.updatedAt,
        replaceExisting: true,
      );
    });
  }

  @override
  Future<void> endSession(ExamSession session) async {
    if (session.status != ExamSessionStatus.cancelled &&
        session.status != ExamSessionStatus.expired) {
      throw ArgumentError(
        'Session must be cancelled or expired before it can be ended.',
      );
    }
    final database = await _database.instance;
    await database.transaction((transaction) async {
      final updated = await transaction.update(
        'exam_sessions',
        _sessionToRow(session),
        where: 'id = ? AND status = ?',
        whereArgs: [session.id, ExamSessionStatus.active.name],
      );
      if (updated != 1) {
        throw StateError('Cannot end inactive session ${session.id}.');
      }
      await _insertOutbox(
        transaction,
        operationId: '${session.id}:${session.status.name}',
        entityType: 'exam_session',
        entityId: session.id,
        operation: session.status.name,
        payload: _sessionToRow(session),
        createdAt: session.updatedAt,
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
      orderBy: 'created_at ASC, operation_id ASC',
      limit: limit,
    );
    return List.unmodifiable(rows.map(_outboxFromRow));
  }

  @override
  Future<List<SyncOutboxItem>> getReady({
    required DateTime now,
    int limit = 50,
  }) async {
    final database = await _database.instance;
    final rows = await database.query(
      'sync_outbox',
      where: 'status = ? AND (next_attempt_at IS NULL OR next_attempt_at <= ?)',
      whereArgs: [
        SyncOutboxStatus.pending.name,
        _ensureUtc(now).toIso8601String(),
      ],
      orderBy: 'created_at ASC, operation_id ASC',
      limit: limit,
    );
    return List.unmodifiable(rows.map(_outboxFromRow));
  }

  @override
  Future<void> markAttemptFailed(
    String operationId,
    String error, {
    required DateTime attemptedAt,
    DateTime? nextAttemptAt,
    required bool deadLetter,
  }) async {
    final database = await _database.instance;
    final attemptedAtUtc = _ensureUtc(attemptedAt);
    await database.rawUpdate(
      '''
      UPDATE sync_outbox
      SET attempts = attempts + 1,
          last_error = ?,
          last_attempt_at = ?,
          next_attempt_at = ?,
          status = ?,
          dead_lettered_at = ?,
          synced_at = NULL,
          acknowledgement = NULL,
          remote_revision = NULL
      WHERE operation_id = ? AND status = ?
      ''',
      [
        _boundedError(error),
        attemptedAtUtc.toIso8601String(),
        nextAttemptAt == null
            ? null
            : _ensureUtc(nextAttemptAt).toIso8601String(),
        deadLetter
            ? SyncOutboxStatus.deadLetter.name
            : SyncOutboxStatus.pending.name,
        deadLetter ? attemptedAtUtc.toIso8601String() : null,
        operationId,
        SyncOutboxStatus.pending.name,
      ],
    );
  }

  @override
  Future<void> markSynced(
    String operationId, {
    required DateTime syncedAt,
    required SyncAcknowledgement acknowledgement,
    int? remoteRevision,
  }) async {
    final database = await _database.instance;
    final syncedAtUtc = _ensureUtc(syncedAt);
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
        {
          'status': SyncOutboxStatus.synced.name,
          'last_error': null,
          'last_attempt_at': syncedAtUtc.toIso8601String(),
          'next_attempt_at': null,
          'synced_at': syncedAtUtc.toIso8601String(),
          'dead_lettered_at': null,
          'acknowledgement': acknowledgement.name,
          'remote_revision': remoteRevision,
        },
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

  @override
  Future<int> pruneSynced({required DateTime before, int limit = 200}) async {
    if (limit <= 0) {
      return 0;
    }
    final database = await _database.instance;
    return database.transaction((transaction) async {
      final rows = await transaction.query(
        'sync_outbox',
        columns: const ['operation_id', 'entity_type', 'entity_id'],
        where: 'status = ? AND synced_at IS NOT NULL AND synced_at < ?',
        whereArgs: [
          SyncOutboxStatus.synced.name,
          _ensureUtc(before).toIso8601String(),
        ],
        orderBy: 'synced_at ASC',
        limit: limit,
      );
      if (rows.isEmpty) {
        return 0;
      }
      for (final row in rows) {
        if (row['entity_type'] == 'analytics_event') {
          await transaction.delete(
            'analytics_events',
            where: 'id = ? AND upload_status = ?',
            whereArgs: [row['entity_id'], SyncOutboxStatus.synced.name],
          );
        }
      }
      final placeholders = List.filled(rows.length, '?').join(',');
      return transaction.delete(
        'sync_outbox',
        where: 'operation_id IN ($placeholders)',
        whereArgs: rows.map((row) => row['operation_id']).toList(),
      );
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
    selectedOptionId: row['is_skipped'] == 1
        ? null
        : row['selected_option_id']! as String,
    timeSpent: Duration(milliseconds: row['time_spent_ms']! as int),
    answeredAt: DateTime.parse(row['answered_at']! as String),
    changedAnswer: row['changed_answer'] == 1,
  );

  static AnswerEvaluation _evaluationFromRow(Map<String, Object?> row) =>
      AnswerEvaluation(
        questionId: row['question_id']! as String,
        selectedOptionId: row['is_skipped'] == 1
            ? null
            : row['selected_option_id']! as String,
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
    bool replaceExisting = false,
  }) async {
    await executor.insert(
      'sync_outbox',
      {
        'operation_id': operationId,
        'entity_type': entityType,
        'entity_id': entityId,
        'operation': operation,
        'payload_json': jsonEncode(payload),
        'created_at': createdAt.toIso8601String(),
        'attempts': 0,
        'status': SyncOutboxStatus.pending.name,
        'last_error': null,
        'last_attempt_at': null,
        'next_attempt_at': null,
        'synced_at': null,
        'dead_lettered_at': null,
        'acknowledgement': null,
        'remote_revision': null,
      },
      conflictAlgorithm: replaceExisting
          ? ConflictAlgorithm.replace
          : ConflictAlgorithm.ignore,
    );
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
      lastAttemptAt: _dateTimeOrNull(row['last_attempt_at']),
      nextAttemptAt: _dateTimeOrNull(row['next_attempt_at']),
      syncedAt: _dateTimeOrNull(row['synced_at']),
      deadLetteredAt: _dateTimeOrNull(row['dead_lettered_at']),
      acknowledgement: row['acknowledgement'] == null
          ? null
          : SyncAcknowledgement.values.byName(
              row['acknowledgement']! as String,
            ),
      remoteRevision: row['remote_revision'] as int?,
    );
  }

  static DateTime _ensureUtc(DateTime value) =>
      value.isUtc ? value : value.toUtc();

  static DateTime? _dateTimeOrNull(Object? value) =>
      value == null ? null : DateTime.parse(value as String);

  static String _boundedError(String error) =>
      error.length <= 500 ? error : error.substring(0, 500);
}
