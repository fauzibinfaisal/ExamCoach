import 'package:exam_coach/features/subscription/domain/subscription_models.dart';

enum SubscriptionFailureCode {
  authenticationRequired,
  unavailable,
  cancelled,
  store,
  verification,
}

class SubscriptionFailure implements Exception {
  const SubscriptionFailure(this.code, this.message);

  final SubscriptionFailureCode code;
  final String message;

  @override
  String toString() => message;
}

abstract interface class SubscriptionRepository {
  bool get isAvailable;

  String get unavailableReason;

  Future<SubscriptionSnapshot> load();

  Future<SubscriptionSnapshot> purchase(String packageId);

  Future<SubscriptionSnapshot> restore();
}

class UnavailableSubscriptionRepository implements SubscriptionRepository {
  const UnavailableSubscriptionRepository(this.unavailableReason);

  @override
  final String unavailableReason;

  @override
  bool get isAvailable => false;

  @override
  Future<SubscriptionSnapshot> load() => Future.error(
    SubscriptionFailure(SubscriptionFailureCode.unavailable, unavailableReason),
  );

  @override
  Future<SubscriptionSnapshot> purchase(String packageId) => load();

  @override
  Future<SubscriptionSnapshot> restore() => load();
}
