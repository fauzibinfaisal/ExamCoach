import 'package:cloud_functions/cloud_functions.dart';
import 'package:exam_coach/features/subscription/data/subscription_runtime_config.dart';
import 'package:exam_coach/features/subscription/domain/subscription_models.dart';
import 'package:exam_coach/features/subscription/domain/subscription_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as revenuecat;

class RevenueCatSubscriptionRepository implements SubscriptionRepository {
  factory RevenueCatSubscriptionRepository({
    required FirebaseFunctions functions,
    required FirebaseAuth auth,
    required SubscriptionRuntimeConfig config,
  }) => RevenueCatSubscriptionRepository._(
    auth,
    config,
    functions.httpsCallable(
      'refreshSubscriptionEntitlement',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
    ),
  );

  RevenueCatSubscriptionRepository._(
    this._auth,
    this._config,
    this._refreshEntitlement,
  );

  final FirebaseAuth _auth;
  final SubscriptionRuntimeConfig _config;
  final HttpsCallable _refreshEntitlement;
  final Map<String, revenuecat.Package> _packages = {};

  @override
  bool get isAvailable => _config.validationMessage == null;

  @override
  String get unavailableReason =>
      _config.validationMessage ?? 'Langganan belum tersedia.';

  @override
  Future<SubscriptionSnapshot> load() async {
    final uid = _requireUser();
    await _ensureConfigured(uid);
    return _loadSnapshot();
  }

  @override
  Future<SubscriptionSnapshot> purchase(String packageId) async {
    final uid = _requireUser();
    await _ensureConfigured(uid);
    var package = _packages[packageId];
    if (package == null) {
      await _loadOfferings();
      package = _packages[packageId];
    }
    if (package == null) {
      throw const SubscriptionFailure(
        SubscriptionFailureCode.store,
        'Paket tidak lagi tersedia. Muat ulang daftar paket.',
      );
    }
    try {
      await revenuecat.Purchases.purchase(
        revenuecat.PurchaseParams.package(package),
      );
    } on PlatformException catch (error) {
      final code = revenuecat.PurchasesErrorHelper.getErrorCode(error);
      if (code == revenuecat.PurchasesErrorCode.purchaseCancelledError) {
        throw const SubscriptionFailure(
          SubscriptionFailureCode.cancelled,
          'Pembelian dibatalkan; tidak ada perubahan paket.',
        );
      }
      throw SubscriptionFailure(
        SubscriptionFailureCode.store,
        error.message ?? 'Pembelian tidak dapat diproses oleh toko.',
      );
    }
    final snapshot = await _loadSnapshot();
    if (!snapshot.entitlement.isPremium) {
      throw const SubscriptionFailure(
        SubscriptionFailureCode.verification,
        'Pembelian selesai, tetapi entitlement premium belum terverifikasi. Coba pulihkan pembelian atau hubungi dukungan.',
      );
    }
    return snapshot;
  }

  @override
  Future<SubscriptionSnapshot> restore() async {
    final uid = _requireUser();
    await _ensureConfigured(uid);
    try {
      await revenuecat.Purchases.restorePurchases();
    } on PlatformException catch (error) {
      throw SubscriptionFailure(
        SubscriptionFailureCode.store,
        error.message ?? 'Pembelian lama tidak dapat dipulihkan.',
      );
    }
    return _loadSnapshot();
  }

  Future<SubscriptionSnapshot> _loadSnapshot() async {
    final packages = await _loadOfferings();
    final entitlement = await _loadTrustedEntitlement();
    return SubscriptionSnapshot(entitlement: entitlement, packages: packages);
  }

  Future<List<SubscriptionPackage>> _loadOfferings() async {
    try {
      final offering = (await revenuecat.Purchases.getOfferings()).current;
      _packages.clear();
      if (offering == null) return const [];
      final result = <SubscriptionPackage>[];
      for (final package in offering.availablePackages) {
        _packages[package.identifier] = package;
        final product = package.storeProduct;
        result.add(
          SubscriptionPackage(
            packageId: package.identifier,
            productId: product.identifier,
            title: product.title,
            description: product.description,
            price: product.priceString,
            subscriptionPeriod: product.subscriptionPeriod,
          ),
        );
      }
      return List.unmodifiable(result);
    } on PlatformException catch (error) {
      throw SubscriptionFailure(
        SubscriptionFailureCode.store,
        error.message ?? 'Offering RevenueCat tidak dapat dimuat.',
      );
    }
  }

  Future<TrustedEntitlement> _loadTrustedEntitlement() async {
    try {
      final response = await _refreshEntitlement.call(<String, Object?>{
        'protocolVersion': 1,
      });
      final root = _object(response.data, 'subscription response');
      if (root['protocolVersion'] != 1) {
        throw const FormatException('Unsupported subscription protocol.');
      }
      final value = _object(root['entitlement'], 'entitlement');
      return TrustedEntitlement(
        planId: _string(value['planId'], 'planId'),
        status: _string(value['status'], 'status'),
        source: _string(value['source'], 'source'),
        entitlementId: _optionalString(value['entitlementId']),
        expiresAt: _optionalTime(value['expiresAt'], 'expiresAt'),
        checkedAt: _time(value['checkedAt'], 'checkedAt'),
      );
    } on FirebaseFunctionsException catch (error) {
      final code = error.code == 'unauthenticated'
          ? SubscriptionFailureCode.authenticationRequired
          : error.code == 'unavailable'
          ? SubscriptionFailureCode.unavailable
          : SubscriptionFailureCode.verification;
      throw SubscriptionFailure(
        code,
        error.message ?? 'Entitlement belum dapat diverifikasi oleh server.',
      );
    } on SubscriptionFailure {
      rethrow;
    } on Object catch (error) {
      throw SubscriptionFailure(
        SubscriptionFailureCode.verification,
        'Respons entitlement tidak valid: $error',
      );
    }
  }

  Future<void> _ensureConfigured(String uid) async {
    if (!isAvailable) {
      throw SubscriptionFailure(
        SubscriptionFailureCode.unavailable,
        unavailableReason,
      );
    }
    try {
      if (!await revenuecat.Purchases.isConfigured) {
        final configuration = revenuecat.PurchasesConfiguration(_config.apiKey)
          ..appUserID = uid;
        await revenuecat.Purchases.configure(configuration);
        return;
      }
      if (await revenuecat.Purchases.appUserID != uid) {
        await revenuecat.Purchases.logIn(uid);
      }
    } on PlatformException catch (error) {
      throw SubscriptionFailure(
        SubscriptionFailureCode.unavailable,
        error.message ?? 'RevenueCat gagal diinisialisasi.',
      );
    }
  }

  String _requireUser() {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw const SubscriptionFailure(
        SubscriptionFailureCode.authenticationRequired,
        'Masuk ke akun sebelum mengelola langganan.',
      );
    }
    return uid;
  }

  static Map<String, Object?> _object(Object? value, String path) {
    if (value is! Map) throw FormatException('$path must be an object.');
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  static String _string(Object? value, String path) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$path must be a non-empty string.');
    }
    return value;
  }

  static String? _optionalString(Object? value) {
    if (value == null) return null;
    return _string(value, 'optional string');
  }

  static DateTime _time(Object? value, String path) {
    final parsed = DateTime.tryParse(_string(value, path));
    if (parsed == null || !parsed.isUtc) {
      throw FormatException('$path must be a UTC timestamp.');
    }
    return parsed;
  }

  static DateTime? _optionalTime(Object? value, String path) {
    if (value == null) return null;
    return _time(value, path);
  }
}
