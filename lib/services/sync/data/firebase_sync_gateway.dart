import 'package:cloud_functions/cloud_functions.dart';
import 'package:exam_coach/features/exam/domain/models/exam_session.dart';
import 'package:exam_coach/services/sync/domain/remote_learning_snapshot.dart';
import 'package:exam_coach/services/sync/domain/sync_outbox_item.dart';
import 'package:exam_coach/services/sync/domain/sync_remote_gateway.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseSyncGateway implements SyncRemoteGateway, RemoteRecoveryGateway {
  FirebaseSyncGateway({
    required FirebaseFunctions functions,
    required this._auth,
  }) : _pushBatch = functions.httpsCallable(
         'pushSyncBatch',
         options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
       ),
       _pullSnapshot = functions.httpsCallable(
         'pullRecoverySnapshot',
         options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
       );

  final HttpsCallable _pushBatch;
  final HttpsCallable _pullSnapshot;
  final FirebaseAuth _auth;

  @override
  Future<SyncBatchResponse> pushBatch(List<SyncOutboxItem> operations) async {
    _requireAuthenticatedUser();
    try {
      final response = await _pushBatch.call(<String, Object?>{
        'protocolVersion': 1,
        'operations': [
          for (final operation in operations)
            {
              'operationId': operation.operationId,
              'entityType': operation.entityType,
              'entityId': operation.entityId,
              'operation': operation.operation,
              'payload': operation.payload,
              'createdAt': operation.createdAt.toUtc().toIso8601String(),
            },
        ],
      });
      final root = _object(response.data, 'pushSyncBatch response');
      if (_integer(root['protocolVersion'], 'protocolVersion') != 1) {
        throw const SyncTransportException(
          'Unsupported push response protocol version.',
        );
      }
      final rawResults = _list(root['results'], 'results');
      final seenIds = <String>{};
      final results = <SyncRemoteResult>[];
      for (var index = 0; index < rawResults.length; index++) {
        final value = _object(rawResults[index], 'results[$index]');
        final operationId = _string(
          value['operationId'],
          'results[$index].operationId',
        );
        if (!seenIds.add(operationId)) {
          throw SyncTransportException(
            'Remote returned duplicate result for $operationId.',
          );
        }
        results.add(
          SyncRemoteResult(
            operationId: operationId,
            outcome: _outcome(value['outcome'], 'results[$index].outcome'),
            remoteRevision: value['remoteRevision'] == null
                ? null
                : _integer(
                    value['remoteRevision'],
                    'results[$index].remoteRevision',
                  ),
            message: value['message'] is String
                ? (value['message'] as String).trim()
                : null,
          ),
        );
      }
      return SyncBatchResponse(results);
    } on FirebaseFunctionsException catch (error) {
      throw _mapFunctionsError(error);
    } on SyncTransportException {
      rethrow;
    } on Object catch (error) {
      throw SyncTransportException('Invalid Firebase response: $error');
    }
  }

  @override
  Future<RemoteLearningSnapshot> pullSnapshot() async {
    final expectedUid = _requireAuthenticatedUser();
    try {
      final response = await _pullSnapshot.call(<String, Object?>{
        'protocolVersion': 1,
      });
      final root = _object(response.data, 'pullRecoverySnapshot response');
      if (_integer(root['protocolVersion'], 'protocolVersion') != 1) {
        throw const SyncTransportException(
          'Unsupported recovery response protocol version.',
        );
      }
      final userId = _string(root['userId'], 'userId');
      if (userId != expectedUid) {
        throw const SyncTransportException(
          'Recovery response belongs to a different user.',
        );
      }
      final sessions = <ExamSession>[];
      final rawSessions = _list(root['sessions'], 'sessions');
      for (var index = 0; index < rawSessions.length; index++) {
        sessions.add(_session(rawSessions[index], index, userId));
      }
      final answers = <RemoteAnswerRecord>[];
      final rawAnswers = _list(root['answers'], 'answers');
      for (var index = 0; index < rawAnswers.length; index++) {
        answers.add(_answer(rawAnswers[index], index));
      }
      return RemoteLearningSnapshot(
        userId: userId,
        remoteRevision: _integer(root['remoteRevision'], 'remoteRevision'),
        sessions: sessions,
        answers: answers,
      );
    } on FirebaseFunctionsException catch (error) {
      throw _mapFunctionsError(error);
    } on SyncTransportException {
      rethrow;
    } on Object catch (error) {
      throw SyncTransportException('Invalid recovery response: $error');
    }
  }

  String _requireAuthenticatedUser() {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw const SyncAuthenticationException(
        'Firebase authentication is required for remote sync.',
      );
    }
    return uid;
  }

  static ExamSession _session(Object? source, int index, String userId) {
    final value = _object(source, 'sessions[$index]');
    final questionIds = _list(
      value['question_ids'],
      'question_ids',
    ).map((item) => _string(item, 'question_ids item')).toList(growable: false);
    final status = _enumByName(
      ExamSessionStatus.values,
      value['status'],
      'sessions[$index].status',
    );
    return ExamSession(
      id: _string(value['id'], 'sessions[$index].id'),
      userId: userId,
      testId: _string(value['test_id'], 'sessions[$index].test_id'),
      mode: _enumByName(
        ExamSessionMode.values,
        value['mode'],
        'sessions[$index].mode',
      ),
      status: status,
      questionIds: List.unmodifiable(questionIds),
      currentIndex: _integer(
        value['current_index'],
        'sessions[$index].current_index',
      ),
      startedAt: _utcTime(value['started_at'], 'sessions[$index].started_at'),
      updatedAt: _utcTime(value['updated_at'], 'sessions[$index].updated_at'),
      endedAt: value['ended_at'] == null
          ? null
          : _utcTime(value['ended_at'], 'sessions[$index].ended_at'),
      score: value['score'] == null
          ? null
          : _integer(value['score'], 'sessions[$index].score'),
      syncVersion: _integer(
        value['sync_version'],
        'sessions[$index].sync_version',
      ),
    );
  }

  static RemoteAnswerRecord _answer(Object? source, int index) {
    final value = _object(source, 'answers[$index]');
    final skipped = _boolean(value['is_skipped'], 'answers[$index].is_skipped');
    final selected = _string(
      value['selected_option_id'],
      'answers[$index].selected_option_id',
      allowEmpty: true,
    );
    return RemoteAnswerRecord(
      sessionId: _string(value['session_id'], 'answers[$index].session_id'),
      questionId: _string(value['question_id'], 'answers[$index].question_id'),
      position: _integer(value['position'], 'answers[$index].position'),
      selectedOptionId: skipped ? null : selected,
      timeSpent: Duration(
        milliseconds: _integer(
          value['time_spent_ms'],
          'answers[$index].time_spent_ms',
        ),
      ),
      changedAnswer: _boolean(
        value['changed_answer'],
        'answers[$index].changed_answer',
      ),
      answeredAt: _utcTime(value['answered_at'], 'answers[$index].answered_at'),
    );
  }

  static SyncRemoteOutcome _outcome(Object? source, String path) =>
      _enumByName(SyncRemoteOutcome.values, source, path);

  static T _enumByName<T extends Enum>(
    Iterable<T> values,
    Object? source,
    String path,
  ) {
    final name = _string(source, path);
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw SyncTransportException('$path has unsupported value $name.');
  }

  static Map<String, Object?> _object(Object? source, String path) {
    if (source is! Map) {
      throw SyncTransportException('$path must be an object.');
    }
    return source.map((key, value) => MapEntry(key.toString(), value));
  }

  static List<Object?> _list(Object? source, String path) {
    if (source is! List) {
      throw SyncTransportException('$path must be an array.');
    }
    return source;
  }

  static String _string(
    Object? source,
    String path, {
    bool allowEmpty = false,
  }) {
    if (source is! String || (!allowEmpty && source.trim().isEmpty)) {
      throw SyncTransportException('$path must be a string.');
    }
    return source;
  }

  static int _integer(Object? source, String path) {
    if (source is! int) {
      throw SyncTransportException('$path must be an integer.');
    }
    return source;
  }

  static bool _boolean(Object? source, String path) {
    if (source is! bool) {
      throw SyncTransportException('$path must be a boolean.');
    }
    return source;
  }

  static DateTime _utcTime(Object? source, String path) {
    final parsed = DateTime.tryParse(_string(source, path));
    if (parsed == null || !parsed.isUtc) {
      throw SyncTransportException('$path must be an ISO-8601 UTC timestamp.');
    }
    return parsed;
  }

  static SyncTransportException _mapFunctionsError(
    FirebaseFunctionsException error,
  ) {
    if (error.code == 'unauthenticated' || error.code == 'permission-denied') {
      return SyncAuthenticationException(
        error.message ?? 'Firebase authentication is required.',
      );
    }
    return SyncTransportException(
      'Firebase callable ${error.code}: ${error.message ?? 'request failed'}',
    );
  }
}
