import 'package:exam_coach/features/ai_coach/domain/ai_coach_models.dart';

enum AiCoachFailureCode {
  authenticationRequired,
  quotaExhausted,
  unavailable,
  invalidResponse,
  transport,
}

class AiCoachFailure implements Exception {
  const AiCoachFailure(this.code, this.message, {this.quota});

  final AiCoachFailureCode code;
  final String message;
  final AiCoachQuotaStatus? quota;

  @override
  String toString() => message;
}

abstract interface class AiCoachRepository {
  bool get isAvailable;

  Future<AiCoachQuotaStatus> getStatus();

  Future<AiCoachGenerationResult> generate(AiCoachContext context);
}

class UnavailableAiCoachRepository implements AiCoachRepository {
  const UnavailableAiCoachRepository(this.reason);

  final String reason;

  @override
  bool get isAvailable => false;

  @override
  Future<AiCoachGenerationResult> generate(AiCoachContext context) =>
      Future.error(AiCoachFailure(AiCoachFailureCode.unavailable, reason));

  @override
  Future<AiCoachQuotaStatus> getStatus() =>
      Future.error(AiCoachFailure(AiCoachFailureCode.unavailable, reason));
}
