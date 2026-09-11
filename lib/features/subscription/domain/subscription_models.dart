class SubscriptionPackage {
  const SubscriptionPackage({
    required this.packageId,
    required this.productId,
    required this.title,
    required this.description,
    required this.price,
    required this.subscriptionPeriod,
  });

  final String packageId;
  final String productId;
  final String title;
  final String description;
  final String price;
  final String? subscriptionPeriod;
}

class TrustedEntitlement {
  const TrustedEntitlement({
    required this.planId,
    required this.status,
    required this.source,
    required this.checkedAt,
    this.entitlementId,
    this.expiresAt,
  });

  final String planId;
  final String status;
  final String source;
  final String? entitlementId;
  final DateTime? expiresAt;
  final DateTime checkedAt;

  bool get isPremium => status == 'active' && planId != 'free';
}

class SubscriptionSnapshot {
  const SubscriptionSnapshot({
    required this.entitlement,
    required this.packages,
  });

  final TrustedEntitlement entitlement;
  final List<SubscriptionPackage> packages;
}
