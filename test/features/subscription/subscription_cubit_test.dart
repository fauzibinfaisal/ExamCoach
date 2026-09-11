import 'package:exam_coach/analytics/analytics_events.dart';
import 'package:exam_coach/features/auth/domain/user_identity.dart';
import 'package:exam_coach/features/subscription/application/subscription_cubit.dart';
import 'package:exam_coach/features/subscription/application/subscription_state.dart';
import 'package:exam_coach/features/subscription/domain/subscription_models.dart';
import 'package:exam_coach/features/subscription/domain/subscription_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('requires authentication before loading a configured paywall', () async {
    final cubit = SubscriptionCubit(
      repository: _FakeSubscriptionRepository(),
      userIdentity: UserIdentity(),
      analytics: InMemoryAnalytics(),
    );
    addTearDown(cubit.close);

    await cubit.refresh();

    expect(cubit.state.status, SubscriptionViewStatus.signedOut);
  });

  test('purchases and restores using server-verified entitlement', () async {
    final identity = UserIdentity(boundUserId: 'user_123')
      ..bindAuthenticatedUser('user_123');
    final analytics = InMemoryAnalytics();
    final repository = _FakeSubscriptionRepository();
    final cubit = SubscriptionCubit(
      repository: repository,
      userIdentity: identity,
      analytics: analytics,
    );
    addTearDown(cubit.close);

    await cubit.recordPaywallViewed();
    await cubit.refresh();
    expect(cubit.state.status, SubscriptionViewStatus.ready);
    expect(cubit.state.packages.single.price, 'Rp49.000');

    await cubit.purchase('monthly');
    expect(cubit.state.status, SubscriptionViewStatus.success);
    expect(cubit.state.entitlement?.planId, 'premium_1');
    expect(repository.purchasedPackageId, 'monthly');

    await cubit.restore();
    expect(repository.restoreCalled, isTrue);
    expect(
      analytics.events.map((event) => event.name),
      containsAll([
        AnalyticsEvents.paywallViewed,
        AnalyticsEvents.purchaseStarted,
        AnalyticsEvents.subscriptionStarted,
        AnalyticsEvents.restorePurchase,
      ]),
    );
  });
}

class _FakeSubscriptionRepository implements SubscriptionRepository {
  String? purchasedPackageId;
  bool restoreCalled = false;

  @override
  bool get isAvailable => true;

  @override
  String get unavailableReason => '';

  @override
  Future<SubscriptionSnapshot> load() async => _snapshot('free', 'inactive');

  @override
  Future<SubscriptionSnapshot> purchase(String packageId) async {
    purchasedPackageId = packageId;
    return _snapshot('premium_1', 'active');
  }

  @override
  Future<SubscriptionSnapshot> restore() async {
    restoreCalled = true;
    return _snapshot('premium_1', 'active');
  }
}

SubscriptionSnapshot _snapshot(String planId, String status) =>
    SubscriptionSnapshot(
      entitlement: TrustedEntitlement(
        planId: planId,
        status: status,
        source: 'revenuecat',
        checkedAt: DateTime.utc(2026, 9, 11),
      ),
      packages: const [
        SubscriptionPackage(
          packageId: 'monthly',
          productId: 'premium_monthly',
          title: 'Premium Bulanan',
          description: 'Akses premium bulanan',
          price: 'Rp49.000',
          subscriptionPeriod: 'P1M',
        ),
      ],
    );
