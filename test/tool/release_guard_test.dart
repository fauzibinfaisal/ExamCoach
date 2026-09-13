import '../../tool/release_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts a pre-1.0 milestone version with monotonic build', () {
    final version = parseDevelopmentVersion('version: 0.12.0+12\n');

    expect(version.major, 0);
    expect(version.minor, 12);
    expect(version.build, 12);
  });

  test('rejects stable or malformed development versions', () {
    expect(
      () => parseDevelopmentVersion('version: 1.0.0+12\n'),
      throwsFormatException,
    );
    expect(
      () => parseDevelopmentVersion('version: 0.12.0\n'),
      throwsFormatException,
    );
    expect(
      () => parseDevelopmentVersion('version: 0.12.0+11\n'),
      throwsFormatException,
    );
  });

  test('enforces the debug APK size budget boundary', () {
    expect(() => enforceDebugApkBudget(maxDebugApkBytes), returnsNormally);
    expect(
      () => enforceDebugApkBudget(maxDebugApkBytes + 1),
      throwsFormatException,
    );
  });
}
