import 'package:exam_coach/features/subscription/domain/subscription_models.dart';

enum SubscriptionViewStatus {
  initial,
  unavailable,
  signedOut,
  loading,
  ready,
  success,
  cancelled,
  failure,
}

class SubscriptionState {
  const SubscriptionState({
    this.status = SubscriptionViewStatus.initial,
    this.entitlement,
    this.packages = const [],
    this.message,
  });

  final SubscriptionViewStatus status;
  final TrustedEntitlement? entitlement;
  final List<SubscriptionPackage> packages;
  final String? message;
}
