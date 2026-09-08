import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

enum FirebaseRuntimeStatus { disabled, ready, invalidConfiguration, failed }

class FirebaseRuntimeConfig {
  const FirebaseRuntimeConfig({
    required this.enabled,
    required this.projectId,
    required this.apiKey,
    required this.messagingSenderId,
    required this.androidAppId,
    required this.iosAppId,
    required this.iosBundleId,
    required this.functionsRegion,
    required this.useEmulators,
    required this.emulatorHost,
  });

  factory FirebaseRuntimeConfig.fromEnvironment() =>
      const FirebaseRuntimeConfig(
        enabled: bool.fromEnvironment('EXAMCOACH_FIREBASE_ENABLED'),
        projectId: String.fromEnvironment('EXAMCOACH_FIREBASE_PROJECT_ID'),
        apiKey: String.fromEnvironment('EXAMCOACH_FIREBASE_API_KEY'),
        messagingSenderId: String.fromEnvironment(
          'EXAMCOACH_FIREBASE_MESSAGING_SENDER_ID',
        ),
        androidAppId: String.fromEnvironment(
          'EXAMCOACH_FIREBASE_ANDROID_APP_ID',
        ),
        iosAppId: String.fromEnvironment('EXAMCOACH_FIREBASE_IOS_APP_ID'),
        iosBundleId: String.fromEnvironment(
          'EXAMCOACH_FIREBASE_IOS_BUNDLE_ID',
          defaultValue: 'id.examcoach.examCoach',
        ),
        functionsRegion: String.fromEnvironment(
          'EXAMCOACH_FIREBASE_FUNCTIONS_REGION',
          defaultValue: 'asia-southeast2',
        ),
        useEmulators: bool.fromEnvironment('EXAMCOACH_FIREBASE_USE_EMULATORS'),
        emulatorHost: String.fromEnvironment(
          'EXAMCOACH_FIREBASE_EMULATOR_HOST',
          defaultValue: '127.0.0.1',
        ),
      );

  final bool enabled;
  final String projectId;
  final String apiKey;
  final String messagingSenderId;
  final String androidAppId;
  final String iosAppId;
  final String iosBundleId;
  final String functionsRegion;
  final bool useEmulators;
  final String emulatorHost;

  List<String> get missingFields {
    if (!enabled) {
      return const [];
    }
    final missing = <String>[];
    if (projectId.trim().isEmpty) missing.add('PROJECT_ID');
    if (apiKey.trim().isEmpty) missing.add('API_KEY');
    if (messagingSenderId.trim().isEmpty) missing.add('MESSAGING_SENDER_ID');
    if (androidAppId.trim().isEmpty) missing.add('ANDROID_APP_ID');
    if (iosAppId.trim().isEmpty) missing.add('IOS_APP_ID');
    if (iosBundleId.trim().isEmpty) missing.add('IOS_BUNDLE_ID');
    if (functionsRegion.trim().isEmpty) missing.add('FUNCTIONS_REGION');
    if (emulatorHost.trim().isEmpty) missing.add('EMULATOR_HOST');
    return List.unmodifiable(missing);
  }

  FirebaseOptions optionsFor(TargetPlatform platform) {
    final appId = platform == TargetPlatform.iOS ? iosAppId : androidAppId;
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      iosBundleId: platform == TargetPlatform.iOS ? iosBundleId : null,
    );
  }
}

class FirebaseRuntimeServices {
  const FirebaseRuntimeServices({
    required this.auth,
    required this.functions,
    required this.config,
  });

  final FirebaseAuth auth;
  final FirebaseFunctions functions;
  final FirebaseRuntimeConfig config;
}

class FirebaseRuntimeResult {
  const FirebaseRuntimeResult({
    required this.status,
    required this.message,
    this.services,
  });

  final FirebaseRuntimeStatus status;
  final String message;
  final FirebaseRuntimeServices? services;
}

class FirebaseRuntimeInitializer {
  const FirebaseRuntimeInitializer();

  Future<FirebaseRuntimeResult> initialize({
    FirebaseRuntimeConfig? config,
  }) async {
    final resolved = config ?? FirebaseRuntimeConfig.fromEnvironment();
    if (!resolved.enabled) {
      return const FirebaseRuntimeResult(
        status: FirebaseRuntimeStatus.disabled,
        message:
            'Firebase belum dikonfigurasi. Mode belajar lokal tetap aktif.',
      );
    }
    final missing = resolved.missingFields;
    if (missing.isNotEmpty) {
      return FirebaseRuntimeResult(
        status: FirebaseRuntimeStatus.invalidConfiguration,
        message: 'Konfigurasi Firebase belum lengkap: ${missing.join(', ')}.',
      );
    }
    try {
      final app = Firebase.apps.isEmpty
          ? await Firebase.initializeApp(
              options: resolved.optionsFor(defaultTargetPlatform),
            )
          : Firebase.app();
      final auth = FirebaseAuth.instanceFor(app: app);
      final functions = FirebaseFunctions.instanceFor(
        app: app,
        region: resolved.functionsRegion,
      );
      if (resolved.useEmulators) {
        await auth.useAuthEmulator(resolved.emulatorHost, 9099);
        functions.useFunctionsEmulator(resolved.emulatorHost, 5001);
      }
      return FirebaseRuntimeResult(
        status: FirebaseRuntimeStatus.ready,
        message: resolved.useEmulators
            ? 'Firebase Emulator terhubung.'
            : 'Firebase terhubung.',
        services: FirebaseRuntimeServices(
          auth: auth,
          functions: functions,
          config: resolved,
        ),
      );
    } on Object catch (error) {
      return FirebaseRuntimeResult(
        status: FirebaseRuntimeStatus.failed,
        message:
            'Firebase gagal diinisialisasi; mode lokal tetap aktif: $error',
      );
    }
  }
}
