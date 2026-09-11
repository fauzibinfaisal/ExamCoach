import 'package:exam_coach/features/ai_coach/domain/ai_coach_models.dart';

enum AiCoachStatus {
  initial,
  noLearningData,
  signedOut,
  unavailable,
  ready,
  loading,
  success,
  quotaExhausted,
  failure,
}

class AiCoachState {
  const AiCoachState({
    this.status = AiCoachStatus.initial,
    this.context,
    this.quota,
    this.insight,
    this.message,
  });

  final AiCoachStatus status;
  final AiCoachContext? context;
  final AiCoachQuotaStatus? quota;
  final AiCoachInsight? insight;
  final String? message;

  bool get hasInsight => insight != null;
}
