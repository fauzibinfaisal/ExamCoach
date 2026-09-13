import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

abstract final class ObservabilityRuntime {
  static bool _installed = false;

  static Future<void> configure({
    required FirebaseCrashlytics crashlytics,
    required bool enabled,
  }) async {
    await crashlytics.setCrashlyticsCollectionEnabled(enabled);
    if (!enabled || _installed) return;

    _installed = true;
    FlutterError.onError = crashlytics.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      unawaited(
        crashlytics.recordError(
          error,
          stackTrace,
          fatal: true,
          reason: 'Unhandled asynchronous application error',
          printDetails: kDebugMode,
        ),
      );
      return true;
    };
  }
}
