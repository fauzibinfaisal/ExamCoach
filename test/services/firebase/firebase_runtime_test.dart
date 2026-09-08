import 'package:exam_coach/services/firebase/firebase_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports every required field when Firebase is explicitly enabled', () {
    const config = FirebaseRuntimeConfig(
      enabled: true,
      projectId: '',
      apiKey: '',
      messagingSenderId: '',
      androidAppId: '',
      iosAppId: '',
      iosBundleId: '',
      functionsRegion: '',
      useEmulators: false,
      emulatorHost: '',
    );

    expect(
      config.missingFields,
      containsAll({
        'PROJECT_ID',
        'API_KEY',
        'MESSAGING_SENDER_ID',
        'ANDROID_APP_ID',
        'IOS_APP_ID',
        'IOS_BUNDLE_ID',
        'FUNCTIONS_REGION',
        'EMULATOR_HOST',
      }),
    );
  });

  test('builds platform-specific Firebase options without config files', () {
    const config = FirebaseRuntimeConfig(
      enabled: true,
      projectId: 'examcoach-dev',
      apiKey: 'test-api-key',
      messagingSenderId: '123456789',
      androidAppId: '1:123456789:android:abc',
      iosAppId: '1:123456789:ios:def',
      iosBundleId: 'id.examcoach.examCoach',
      functionsRegion: 'asia-southeast2',
      useEmulators: true,
      emulatorHost: '127.0.0.1',
    );

    expect(config.missingFields, isEmpty);
    expect(
      config.optionsFor(TargetPlatform.android).appId,
      contains('android'),
    );
    expect(config.optionsFor(TargetPlatform.android).iosBundleId, isNull);
    expect(config.optionsFor(TargetPlatform.iOS).appId, contains('ios'));
    expect(
      config.optionsFor(TargetPlatform.iOS).iosBundleId,
      'id.examcoach.examCoach',
    );
  });
}
