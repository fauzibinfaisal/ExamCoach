import 'dart:convert';
import 'dart:io';

import 'package:exam_coach/features/ai_coach/data/local_ai_coach_cache_store.dart';
import 'package:exam_coach/features/ai_coach/domain/ai_coach_models.dart';
import 'package:exam_coach/services/database/exam_coach_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path_util;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late ExamCoachDatabase database;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'exam_coach_ai_cache_test_',
    );
    database = ExamCoachDatabase(
      databasePath: path_util.join(temporaryDirectory.path, 'cache.sqlite'),
      factory: databaseFactoryFfi,
    );
    final opened = await database.instance;
    final timestamp = DateTime.utc(2026, 9, 11, 9).toIso8601String();
    await opened.insert('exam_sessions', {
      'id': 'session_123',
      'user_id': 'user_123',
      'test_id': 'test_tiu',
      'mode': 'tryout',
      'status': 'completed',
      'question_ids_json': jsonEncode(['q_ratio_01']),
      'current_index': 1,
      'started_at': timestamp,
      'updated_at': timestamp,
      'ended_at': timestamp,
      'score': 50,
      'sync_version': 2,
    });
  });

  tearDown(() async {
    await database.close();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('persists valid insight and deletes it after expiry', () async {
    final store = LocalAiCoachCacheStore(database);
    final generatedAt = DateTime.utc(2026, 9, 11, 10);
    final insight = AiCoachInsight(
      contextKey: List.filled(64, 'a').join(),
      summary: 'Ringkasan',
      weaknessExplanation: 'Penjelasan kelemahan',
      whyItMatters: 'Alasan prioritas',
      studyPlan: const [],
      motivation: 'Tetap konsisten.',
      generatedAt: generatedAt,
      expiresAt: generatedAt.add(const Duration(hours: 1)),
      provider: 'openai',
      model: 'configured-model',
      promptVersion: 'ai_coach_v1',
    );

    await store.save(
      userId: 'user_123',
      sourceSessionId: 'session_123',
      insight: insight,
    );
    final cached = await store.load(
      userId: 'user_123',
      contextKey: insight.contextKey,
      now: generatedAt.add(const Duration(minutes: 30)),
    );

    expect(cached?.summary, insight.summary);
    expect(cached?.fromServerCache, isTrue);

    expect(
      await store.load(
        userId: 'user_123',
        contextKey: insight.contextKey,
        now: generatedAt.add(const Duration(hours: 2)),
      ),
      isNull,
    );
    final rows = await (await database.instance).query('ai_coach_insights');
    expect(rows, isEmpty);
  });
}
