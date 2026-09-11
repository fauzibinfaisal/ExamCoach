import 'dart:convert';

import 'package:exam_coach/features/auth/domain/account_data_store.dart';
import 'package:exam_coach/features/auth/domain/user_identity.dart';
import 'package:exam_coach/features/exam/domain/models/exam_session.dart';
import 'package:exam_coach/services/database/exam_coach_database.dart';
import 'package:exam_coach/services/sync/domain/remote_learning_snapshot.dart';
import 'package:sqflite/sqflite.dart';

class LocalAccountDataStore implements AccountDataStore {
  LocalAccountDataStore(this._database);

  final ExamCoachDatabase _database;

  @override
  Future<String?> loadBoundUserId() async {
    final database = await _database.instance;
    final rows = await database.query(
      'account_binding',
      columns: const ['firebase_uid'],
      where: 'singleton = 1',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['firebase_uid']! as String;
  }

  @override
  Future<AccountClaimResult> claimForUser(
    String userId, {
    required DateTime claimedAt,
  }) async {
    _checkUserId(userId);
    final database = await _database.instance;
    return database.transaction((transaction) async {
      final bindingRows = await transaction.query(
        'account_binding',
        where: 'singleton = 1',
        limit: 1,
      );
      if (bindingRows.isNotEmpty) {
        final boundUserId = bindingRows.single['firebase_uid']! as String;
        if (boundUserId != userId) {
          throw AccountBindingConflict(
            boundUserId: boundUserId,
            requestedUserId: userId,
          );
        }
        await _rejectUnexpectedOwners(transaction, userId);
        final migratedSessions = await transaction.update(
          'exam_sessions',
          {'user_id': userId},
          where: 'user_id = ?',
          whereArgs: const [UserIdentity.localUserId],
        );
        final migratedAnalytics = await transaction.update(
          'analytics_events',
          {'user_id': userId},
          where: 'user_id = ?',
          whereArgs: const [UserIdentity.localUserId],
        );
        final rewrittenOutbox = await _rewriteOutboxOwners(transaction, userId);
        return AccountClaimResult(
          userId: userId,
          newBinding: false,
          migratedSessions: migratedSessions,
          migratedAnalyticsEvents: migratedAnalytics,
          rewrittenOutboxOperations: rewrittenOutbox,
        );
      }

      await _rejectUnexpectedOwners(transaction, userId);
      final migratedSessions = await transaction.update(
        'exam_sessions',
        {'user_id': userId},
        where: 'user_id = ?',
        whereArgs: const [UserIdentity.localUserId],
      );
      final migratedAnalytics = await transaction.update(
        'analytics_events',
        {'user_id': userId},
        where: 'user_id = ?',
        whereArgs: const [UserIdentity.localUserId],
      );
      final rewrittenOutbox = await _rewriteOutboxOwners(transaction, userId);
      await transaction.insert('account_binding', {
        'singleton': 1,
        'firebase_uid': userId,
        'bound_at': _utc(claimedAt).toIso8601String(),
        'last_recovered_at': null,
        'remote_revision': 0,
      });
      return AccountClaimResult(
        userId: userId,
        newBinding: true,
        migratedSessions: migratedSessions,
        migratedAnalyticsEvents: migratedAnalytics,
        rewrittenOutboxOperations: rewrittenOutbox,
      );
    });
  }

  @override
  Future<RecoveryImportResult> importRecoverySnapshot(
    RemoteLearningSnapshot snapshot, {
    required DateTime recoveredAt,
  }) async {
    final database = await _database.instance;
    return database.transaction((transaction) async {
      final bindingRows = await transaction.query(
        'account_binding',
        columns: const ['firebase_uid'],
        where: 'singleton = 1',
        limit: 1,
      );
      if (bindingRows.isEmpty ||
          bindingRows.single['firebase_uid'] != snapshot.userId) {
        throw StateError('Recovery requires a matching local account binding.');
      }
      final sessionCount = Sqflite.firstIntValue(
        await transaction.rawQuery('SELECT COUNT(*) FROM exam_sessions'),
      )!;
      if (sessionCount > 0) {
        return const RecoveryImportResult(
          status: RecoveryImportStatus.skippedLocalData,
        );
      }
      final validated = await _validateSnapshot(transaction, snapshot);
      if (snapshot.sessions.isEmpty) {
        await _recordRecovery(transaction, snapshot, recoveredAt);
        return const RecoveryImportResult(
          status: RecoveryImportStatus.emptyRemote,
        );
      }

      for (final session in validated.sessions) {
        await transaction.insert('exam_sessions', _sessionRow(session));
      }
      for (final answer in validated.answers) {
        await transaction.insert('user_answers', answer);
      }
      await _recordRecovery(transaction, snapshot, recoveredAt);
      return RecoveryImportResult(
        status: RecoveryImportStatus.imported,
        sessionCount: validated.sessions.length,
        answerCount: validated.answers.length,
      );
    });
  }

  Future<_ValidatedRecovery> _validateSnapshot(
    DatabaseExecutor database,
    RemoteLearningSnapshot snapshot,
  ) async {
    _checkUserId(snapshot.userId);
    if (snapshot.remoteRevision < 0 || snapshot.sessions.length > 200) {
      throw StateError('Remote recovery metadata is outside allowed bounds.');
    }
    if (snapshot.answers.length > 5000) {
      throw StateError('Remote recovery contains too many answers.');
    }
    final questionRows = await database.query(
      'questions',
      columns: const ['id', 'options_json', 'correct_option_id'],
    );
    final questions = {
      for (final row in questionRows) row['id']! as String: row,
    };
    final sessionsById = <String, ExamSession>{};
    var activeCount = 0;
    for (final session in snapshot.sessions) {
      if (session.userId != snapshot.userId ||
          !_safeDocumentId(session.id) ||
          !_safeDocumentId(session.testId) ||
          !sessionsById.addIfAbsent(session.id, session)) {
        throw StateError('Remote recovery contains invalid session ownership.');
      }
      if (session.questionIds.isEmpty ||
          session.questionIds.toSet().length != session.questionIds.length ||
          session.currentIndex < 0 ||
          session.currentIndex > session.questionIds.length ||
          session.syncVersion < 1 ||
          !session.startedAt.isUtc ||
          !session.updatedAt.isUtc ||
          session.updatedAt.isBefore(session.startedAt) ||
          session.questionIds.any((id) => !questions.containsKey(id))) {
        throw StateError('Remote session ${session.id} is inconsistent.');
      }
      if (session.status == ExamSessionStatus.active) {
        activeCount++;
        if (session.endedAt != null || session.score != null) {
          throw StateError('Active remote session ${session.id} is terminal.');
        }
      } else {
        final endedAt = session.endedAt;
        if (endedAt == null ||
            !endedAt.isUtc ||
            endedAt.isBefore(session.startedAt) ||
            endedAt.isBefore(session.updatedAt)) {
          throw StateError(
            'Terminal remote session ${session.id} has an invalid end.',
          );
        }
        if (session.status == ExamSessionStatus.completed &&
            session.currentIndex != session.questionIds.length) {
          throw StateError(
            'Completed remote session ${session.id} has invalid progress.',
          );
        }
      }
    }
    if (activeCount > 1) {
      throw StateError('Remote recovery contains multiple active sessions.');
    }

    final answersBySession = <String, List<Map<String, Object?>>>{};
    final answerKeys = <String>{};
    for (final answer in snapshot.answers) {
      final session = sessionsById[answer.sessionId];
      final key = '${answer.sessionId}:${answer.questionId}';
      if (session == null || !answerKeys.add(key)) {
        throw StateError(
          'Remote recovery contains an orphan/duplicate answer.',
        );
      }
      if (answer.position < 0 ||
          answer.position >= session.questionIds.length ||
          session.questionIds[answer.position] != answer.questionId ||
          answer.timeSpent.isNegative ||
          !answer.answeredAt.isUtc ||
          answer.answeredAt.isBefore(session.startedAt) ||
          answer.answeredAt.isAfter(session.updatedAt) ||
          (session.endedAt != null &&
              answer.answeredAt.isAfter(session.endedAt!))) {
        throw StateError(
          'Remote answer $key has invalid position or duration.',
        );
      }
      final question = questions[answer.questionId]!;
      final optionRows =
          jsonDecode(question['options_json']! as String) as List;
      final optionIds = optionRows
          .map((item) => (item as Map<String, dynamic>)['id']! as String)
          .toSet();
      final selected = answer.selectedOptionId;
      if (selected != null && !optionIds.contains(selected)) {
        throw StateError('Remote answer $key selects an unknown option.');
      }
      final correctOptionId = question['correct_option_id']! as String;
      answersBySession.putIfAbsent(answer.sessionId, () => []).add({
        'session_id': answer.sessionId,
        'question_id': answer.questionId,
        'position': answer.position,
        'selected_option_id': selected ?? '',
        'correct_option_id': correctOptionId,
        'is_correct': selected == correctOptionId ? 1 : 0,
        'is_skipped': selected == null ? 1 : 0,
        'time_spent_ms': answer.timeSpent.inMilliseconds,
        'changed_answer': answer.changedAnswer ? 1 : 0,
        'answered_at': answer.answeredAt.toIso8601String(),
      });
    }

    final normalizedSessions = <ExamSession>[];
    for (final session in snapshot.sessions) {
      final answers = answersBySession[session.id] ?? const [];
      if (session.status == ExamSessionStatus.completed &&
          answers.length != session.questionIds.length) {
        throw StateError(
          'Completed remote session ${session.id} is incomplete.',
        );
      }
      final correct = answers.where((row) => row['is_correct'] == 1).length;
      final score = session.status == ExamSessionStatus.completed
          ? ((correct / session.questionIds.length) * 100).round()
          : null;
      normalizedSessions.add(
        ExamSession(
          id: session.id,
          userId: session.userId,
          testId: session.testId,
          mode: session.mode,
          status: session.status,
          questionIds: session.questionIds,
          currentIndex: session.currentIndex,
          startedAt: session.startedAt,
          updatedAt: session.updatedAt,
          endedAt: session.endedAt,
          score: score,
          syncVersion: session.syncVersion,
        ),
      );
    }
    return _ValidatedRecovery(
      sessions: normalizedSessions,
      answers: [for (final rows in answersBySession.values) ...rows],
    );
  }

  static Future<void> _rejectUnexpectedOwners(
    DatabaseExecutor transaction,
    String requestedUserId,
  ) async {
    for (final table in const [
      'exam_sessions',
      'analytics_events',
      'ai_coach_insights',
    ]) {
      final rows = await transaction.rawQuery(
        'SELECT DISTINCT user_id FROM $table',
      );
      for (final row in rows) {
        final owner = row['user_id'] as String?;
        if (owner != null &&
            owner != UserIdentity.localUserId &&
            owner != requestedUserId) {
          throw AccountBindingConflict(
            boundUserId: owner,
            requestedUserId: requestedUserId,
          );
        }
      }
    }
  }

  static Future<int> _rewriteOutboxOwners(
    DatabaseExecutor transaction,
    String userId,
  ) async {
    final rows = await transaction.query(
      'sync_outbox',
      columns: const ['operation_id', 'payload_json'],
    );
    var rewritten = 0;
    for (final row in rows) {
      final decoded = jsonDecode(row['payload_json']! as String);
      if (decoded is! Map) {
        throw StateError('Outbox payload must be an object.');
      }
      final payload = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final owner = payload['user_id'];
      if (owner != null &&
          owner != UserIdentity.localUserId &&
          owner != userId) {
        throw AccountBindingConflict(
          boundUserId: owner.toString(),
          requestedUserId: userId,
        );
      }
      if (owner != UserIdentity.localUserId) {
        continue;
      }
      payload['user_id'] = userId;
      rewritten += await transaction.update(
        'sync_outbox',
        {'payload_json': jsonEncode(payload)},
        where: 'operation_id = ?',
        whereArgs: [row['operation_id']],
      );
    }
    return rewritten;
  }

  static Future<void> _recordRecovery(
    DatabaseExecutor transaction,
    RemoteLearningSnapshot snapshot,
    DateTime recoveredAt,
  ) async {
    await transaction.update(
      'account_binding',
      {
        'last_recovered_at': _utc(recoveredAt).toIso8601String(),
        'remote_revision': snapshot.remoteRevision,
      },
      where: 'singleton = 1 AND firebase_uid = ?',
      whereArgs: [snapshot.userId],
    );
  }

  static Map<String, Object?> _sessionRow(ExamSession session) => {
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

  static bool _safeDocumentId(String value) =>
      value.isNotEmpty && value.length <= 240 && !value.contains('/');

  static void _checkUserId(String value) {
    if (!_safeDocumentId(value)) {
      throw ArgumentError.value(value, 'userId', 'is not a safe identifier');
    }
  }

  static DateTime _utc(DateTime value) => value.isUtc ? value : value.toUtc();
}

class _ValidatedRecovery {
  const _ValidatedRecovery({required this.sessions, required this.answers});

  final List<ExamSession> sessions;
  final List<Map<String, Object?>> answers;
}

extension on Map<String, ExamSession> {
  bool addIfAbsent(String key, ExamSession value) {
    if (containsKey(key)) return false;
    this[key] = value;
    return true;
  }
}
