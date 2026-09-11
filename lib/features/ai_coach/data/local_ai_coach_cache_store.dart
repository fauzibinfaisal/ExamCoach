import 'dart:convert';

import 'package:exam_coach/features/ai_coach/domain/ai_coach_cache_store.dart';
import 'package:exam_coach/features/ai_coach/domain/ai_coach_models.dart';
import 'package:exam_coach/services/database/exam_coach_database.dart';
import 'package:sqflite/sqflite.dart';

class LocalAiCoachCacheStore implements AiCoachCacheStore {
  const LocalAiCoachCacheStore(this._database);

  final ExamCoachDatabase _database;

  @override
  Future<AiCoachInsight?> load({
    required String userId,
    required String contextKey,
    required DateTime now,
  }) async {
    final database = await _database.instance;
    final rows = await database.query(
      'ai_coach_insights',
      columns: const ['response_json', 'expires_at'],
      where: 'user_id = ? AND context_key = ?',
      whereArgs: [userId, contextKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final expiresAt = DateTime.parse(rows.single['expires_at']! as String);
    if (!expiresAt.isAfter(_utc(now))) {
      await database.delete(
        'ai_coach_insights',
        where: 'user_id = ? AND context_key = ?',
        whereArgs: [userId, contextKey],
      );
      return null;
    }
    final decoded = jsonDecode(rows.single['response_json']! as String);
    if (decoded is! Map) {
      throw const FormatException('Cached AI Coach response is invalid.');
    }
    return AiCoachInsight.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    ).asLocalCache();
  }

  @override
  Future<void> save({
    required String userId,
    required String sourceSessionId,
    required AiCoachInsight insight,
  }) async {
    final database = await _database.instance;
    await database.insert('ai_coach_insights', {
      'context_key': insight.contextKey,
      'user_id': userId,
      'source_session_id': sourceSessionId,
      'prompt_version': insight.promptVersion,
      'provider': insight.provider,
      'model': insight.model,
      'response_json': jsonEncode(insight.toJson()),
      'generated_at': insight.generatedAt.toUtc().toIso8601String(),
      'expires_at': insight.expiresAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

DateTime _utc(DateTime value) => value.isUtc ? value : value.toUtc();
