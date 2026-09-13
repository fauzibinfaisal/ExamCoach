import 'dart:io';

import 'release_guard.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/check_apk_budget.dart <apk-path>');
    exitCode = 2;
    return;
  }
  final artifact = File(arguments.single);
  if (!artifact.existsSync()) {
    stderr.writeln('APK does not exist: ${artifact.path}');
    exitCode = 2;
    return;
  }
  final bytes = artifact.lengthSync();
  try {
    enforceDebugApkBudget(bytes);
    stdout.writeln(
      'APK budget OK: $bytes / $maxDebugApkBytes bytes '
      '(${(bytes / 1024 / 1024).toStringAsFixed(1)} MiB).',
    );
  } on FormatException catch (error) {
    stderr.writeln('APK budget failed: ${error.message}');
    exitCode = 1;
  }
}
