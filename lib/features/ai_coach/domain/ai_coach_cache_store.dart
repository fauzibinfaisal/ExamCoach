import 'package:exam_coach/features/ai_coach/domain/ai_coach_models.dart';

abstract interface class AiCoachCacheStore {
  Future<AiCoachInsight?> load({
    required String userId,
    required String contextKey,
    required DateTime now,
  });

  Future<void> save({
    required String userId,
    required String sourceSessionId,
    required AiCoachInsight insight,
  });
}

class MemoryAiCoachCacheStore implements AiCoachCacheStore {
  final Map<String, AiCoachInsight> _entries = {};

  @override
  Future<AiCoachInsight?> load({
    required String userId,
    required String contextKey,
    required DateTime now,
  }) async {
    final insight = _entries['$userId:$contextKey'];
    if (insight == null || !insight.expiresAt.isAfter(_utc(now))) return null;
    return insight.asLocalCache();
  }

  @override
  Future<void> save({
    required String userId,
    required String sourceSessionId,
    required AiCoachInsight insight,
  }) async {
    _entries['$userId:${insight.contextKey}'] = insight;
  }
}

DateTime _utc(DateTime value) => value.isUtc ? value : value.toUtc();
