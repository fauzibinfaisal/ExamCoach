const int maxDebugApkBytes = 190 * 1024 * 1024;

class DevelopmentVersion {
  const DevelopmentVersion({
    required this.major,
    required this.minor,
    required this.patch,
    required this.build,
  });

  final int major;
  final int minor;
  final int patch;
  final int build;
}

DevelopmentVersion parseDevelopmentVersion(String pubspec) {
  final match = RegExp(
    r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec);
  if (match == null) {
    throw const FormatException('pubspec version must use X.Y.Z+BUILD');
  }
  final version = DevelopmentVersion(
    major: int.parse(match.group(1)!),
    minor: int.parse(match.group(2)!),
    patch: int.parse(match.group(3)!),
    build: int.parse(match.group(4)!),
  );
  if (version.major != 0) {
    throw const FormatException('development builds must remain below 1.0.0');
  }
  if (version.build < version.minor) {
    throw const FormatException('build number must not trail milestone number');
  }
  return version;
}

void enforceDebugApkBudget(int bytes, {int maximumBytes = maxDebugApkBytes}) {
  if (bytes <= 0) throw const FormatException('APK must not be empty');
  if (bytes > maximumBytes) {
    throw FormatException(
      'debug APK is $bytes bytes; budget is $maximumBytes bytes',
    );
  }
}
