import 'dart:io';

import 'release_guard.dart';

void main() {
  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('pubspec.yaml was not found from the current directory.');
    exitCode = 2;
    return;
  }
  try {
    final version = parseDevelopmentVersion(pubspec.readAsStringSync());
    stdout.writeln(
      'Release metadata OK: '
      '${version.major}.${version.minor}.${version.patch}+${version.build}',
    );
  } on FormatException catch (error) {
    stderr.writeln('Release metadata failed: ${error.message}');
    exitCode = 1;
  }
}
