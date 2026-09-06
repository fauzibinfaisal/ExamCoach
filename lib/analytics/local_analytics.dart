import 'dart:convert';

import 'package:exam_coach/analytics/analytics_events.dart';
import 'package:exam_coach/services/database/exam_coach_database.dart';
import 'package:exam_coach/services/sync/domain/sync_outbox_item.dart';
import 'package:sqflite/sqflite.dart';

class LocalAnalytics implements AnalyticsTracker {
  LocalAnalytics(this._database);

  final ExamCoachDatabase _database;
  int _sequence = 0;

  @override
  Future<void> track(
    String name, {
    Map<String, Object> properties = const {},
  }) async {
    final database = await _database.instance;
    final occurredAt = DateTime.now().toUtc();
    final eventId = 'event_${occurredAt.microsecondsSinceEpoch}_${_sequence++}';
    final sessionId = properties['sessionId'] as String?;
    final eventRow = <String, Object?>{
      'id': eventId,
      'event_name': name,
      'event_version': 1,
      'occurred_at': occurredAt.toIso8601String(),
      'user_id': 'local_user',
      'session_id': sessionId,
      'properties_json': jsonEncode(properties),
      'upload_status': SyncOutboxStatus.pending.name,
    };

    await database.transaction((transaction) async {
      await transaction.insert('analytics_events', eventRow);
      await transaction.insert('sync_outbox', {
        'operation_id': 'analytics:$eventId',
        'entity_type': 'analytics_event',
        'entity_id': eventId,
        'operation': 'create',
        'payload_json': jsonEncode(eventRow),
        'created_at': occurredAt.toIso8601String(),
        'attempts': 0,
        'status': SyncOutboxStatus.pending.name,
        'last_error': null,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }
}
