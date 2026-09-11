import 'package:flutter/foundation.dart';

class SubscriptionRuntimeConfig {
  const SubscriptionRuntimeConfig({
    required this.enabled,
    required this.androidApiKey,
    required this.iosApiKey,
  });

  factory SubscriptionRuntimeConfig.fromEnvironment() =>
      const SubscriptionRuntimeConfig(
        enabled: bool.fromEnvironment('EXAMCOACH_REVENUECAT_ENABLED'),
        androidApiKey: String.fromEnvironment(
          'EXAMCOACH_REVENUECAT_ANDROID_API_KEY',
        ),
        iosApiKey: String.fromEnvironment('EXAMCOACH_REVENUECAT_IOS_API_KEY'),
      );

  final bool enabled;
  final String androidApiKey;
  final String iosApiKey;

  bool get isSupportedPlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  String get apiKey => switch (defaultTargetPlatform) {
    TargetPlatform.android => androidApiKey.trim(),
    TargetPlatform.iOS => iosApiKey.trim(),
    _ => '',
  };

  String? get validationMessage {
    if (!enabled) return 'RevenueCat belum diaktifkan untuk build ini.';
    if (!isSupportedPlatform) {
      return 'Pembelian hanya diaktifkan pada build Android dan iOS.';
    }
    if (apiKey.isEmpty) {
      return 'Public SDK key RevenueCat untuk platform ini belum diisi.';
    }
    return null;
  }
}
