import 'package:cloud_functions/cloud_functions.dart';
import 'package:exam_coach/features/ai_coach/domain/ai_coach_models.dart';
import 'package:exam_coach/features/ai_coach/domain/ai_coach_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseAiCoachRepository implements AiCoachRepository {
  factory FirebaseAiCoachRepository({
    required FirebaseFunctions functions,
    required FirebaseAuth auth,
  }) => FirebaseAiCoachRepository._(
    auth,
    functions.httpsCallable(
      'getAiCoachStatus',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    ),
    functions.httpsCallable(
      'requestAiCoachInsight',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
    ),
  );

  FirebaseAiCoachRepository._(this._auth, this._status, this._generate);

  final FirebaseAuth _auth;
  final HttpsCallable _status;
  final HttpsCallable _generate;

  @override
  bool get isAvailable => true;

  @override
  Future<AiCoachQuotaStatus> getStatus() async {
    _requireUser();
    try {
      final response = await _status.call(<String, Object?>{
        'protocolVersion': 1,
      });
      final root = _object(response.data, 'AI Coach status');
      _requireProtocol(root);
      return AiCoachQuotaStatus.fromJson(_object(root['quota'], 'quota'));
    } on FirebaseFunctionsException catch (error) {
      throw _mapFailure(error);
    } on AiCoachFailure {
      rethrow;
    } on Object catch (error) {
      throw AiCoachFailure(
        AiCoachFailureCode.invalidResponse,
        'Respons status AI Coach tidak valid: $error',
      );
    }
  }

  @override
  Future<AiCoachGenerationResult> generate(AiCoachContext context) async {
    _requireUser();
    try {
      final response = await _generate.call(context.toRequestJson());
      final root = _object(response.data, 'AI Coach response');
      _requireProtocol(root);
      final insight = AiCoachInsight.fromJson(
        _object(root['insight'], 'insight'),
      );
      if (insight.contextKey != context.contextKey) {
        throw const AiCoachFailure(
          AiCoachFailureCode.invalidResponse,
          'AI Coach mengembalikan insight untuk konteks yang berbeda.',
        );
      }
      return AiCoachGenerationResult(
        insight: insight,
        quota: AiCoachQuotaStatus.fromJson(_object(root['quota'], 'quota')),
      );
    } on FirebaseFunctionsException catch (error) {
      throw _mapFailure(error);
    } on AiCoachFailure {
      rethrow;
    } on Object catch (error) {
      throw AiCoachFailure(
        AiCoachFailureCode.invalidResponse,
        'Respons AI Coach tidak valid: $error',
      );
    }
  }

  void _requireUser() {
    if (_auth.currentUser?.uid case final uid? when uid.isNotEmpty) return;
    throw const AiCoachFailure(
      AiCoachFailureCode.authenticationRequired,
      'Masuk ke akun untuk menggunakan AI Coach.',
    );
  }

  static void _requireProtocol(Map<String, Object?> root) {
    if (root['protocolVersion'] != 1) {
      throw const AiCoachFailure(
        AiCoachFailureCode.invalidResponse,
        'Versi protokol AI Coach tidak didukung.',
      );
    }
  }

  static AiCoachFailure _mapFailure(FirebaseFunctionsException error) {
    if (error.code == 'unauthenticated' || error.code == 'permission-denied') {
      return AiCoachFailure(
        AiCoachFailureCode.authenticationRequired,
        error.message ?? 'Masuk ke akun untuk menggunakan AI Coach.',
      );
    }
    if (error.code == 'resource-exhausted') {
      AiCoachQuotaStatus? quota;
      try {
        final details = _object(error.details, 'quota details');
        quota = AiCoachQuotaStatus.fromJson(_object(details['quota'], 'quota'));
      } on Object {
        quota = null;
      }
      return AiCoachFailure(
        AiCoachFailureCode.quotaExhausted,
        error.message ?? 'Kuota AI Coach hari ini sudah habis.',
        quota: quota,
      );
    }
    if (error.code == 'failed-precondition' || error.code == 'unavailable') {
      return AiCoachFailure(
        AiCoachFailureCode.unavailable,
        error.message ?? 'AI Coach belum tersedia.',
      );
    }
    return AiCoachFailure(
      AiCoachFailureCode.transport,
      error.message ?? 'AI Coach tidak dapat dihubungi.',
    );
  }

  static Map<String, Object?> _object(Object? value, String path) {
    if (value is! Map) {
      throw FormatException('$path must be an object.');
    }
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
}
