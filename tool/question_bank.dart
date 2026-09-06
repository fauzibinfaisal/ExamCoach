import 'dart:io';

import 'package:exam_coach/features/exam/data/question_bank_manifest.dart';
import 'package:exam_coach/features/exam/data/question_pack_codec.dart';
import 'package:exam_coach/features/exam/data/question_pack_fingerprint.dart';
import 'package:exam_coach/features/exam/data/question_pack_promotion_service.dart';
import 'package:exam_coach/features/exam/data/question_review_codec.dart';
import 'package:exam_coach/features/exam/data/question_similarity_analyzer.dart';
import 'package:exam_coach/features/exam/domain/models/question.dart';
import 'package:exam_coach/features/exam/domain/models/question_pack.dart';

const _defaultBankDirectory = 'assets/question_bank';

Future<void> main(List<String> arguments) async {
  try {
    final command = _Command.parse(arguments);
    switch (command.name) {
      case 'validate':
        final pack = _readPack(command.subject!);
        stdout.writeln(
          'VALID: ${pack.id} (${pack.questions.length} questions, status: ${pack.validationStatus.name})',
        );
        return;
      case 'import':
        await _importPack(command);
        return;
      case 'list':
        _listPacks(command.bankDirectory);
        return;
      case 'similarity':
        _runSimilarity(command);
        return;
      case 'review-template':
        _createReviewTemplate(command);
        return;
      case 'promote':
        _promotePack(command);
        return;
    }
  } on QuestionPackValidationException catch (error) {
    stderr.writeln(error);
    exitCode = 65;
  } on QuestionReviewValidationException catch (error) {
    stderr.writeln(error);
    exitCode = 65;
  } on QuestionPackPromotionException catch (error) {
    stderr.writeln(error);
    exitCode = 65;
  } on FormatException catch (error) {
    stderr.writeln('ERROR: ${error.message}');
    exitCode = 65;
  } on FileSystemException catch (error) {
    stderr.writeln('ERROR: ${error.message} (${error.path ?? 'unknown path'})');
    exitCode = 74;
  } on _UsageException catch (error) {
    stderr.writeln('ERROR: ${error.message}\n');
    _printUsage(stderr);
    exitCode = 64;
  }
}

QuestionPack _readPack(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw FileSystemException('Question pack does not exist', path);
  }
  return const QuestionPackCodec().decode(
    file.readAsStringSync(),
    sourceName: path,
  );
}

Future<void> _importPack(_Command command) async {
  final pack = _readPack(command.subject!);
  if (pack.validationStatus != QuestionValidationStatus.draft) {
    throw const FormatException(
      'Only draft AI output can use import. Use promote for reviewed content.',
    );
  }
  final bank = _loadBank(command.bankDirectory);
  if (bank.entries.containsKey(pack.id)) {
    throw FormatException('Pack ID ${pack.id} already exists in the bank.');
  }
  final existingQuestionIds = <String>{
    for (final entry in bank.entries.values)
      for (final question in entry.pack.questions) question.id,
  };
  final duplicateQuestions = pack.questions
      .map((question) => question.id)
      .where(existingQuestionIds.contains)
      .toList();
  if (duplicateQuestions.isNotEmpty) {
    throw FormatException(
      'Question IDs already exist: ${duplicateQuestions.join(', ')}.',
    );
  }

  _ensureSimilaritySafe(pack, bank.entries.values.map((entry) => entry.pack));

  final fileName = '${pack.id}.json';
  final destination = File('${bank.directory.path}/$fileName');
  if (destination.existsSync()) {
    throw FileSystemException('Destination already exists', destination.path);
  }
  final nextManifest = QuestionBankManifest(
    activePackId: command.activate ? pack.id : bank.manifest.activePackId,
    packFiles: List.unmodifiable([...bank.manifest.packFiles, fileName]),
  );
  _writePackAndManifest(
    pack: pack,
    destination: destination,
    manifestFile: bank.manifestFile,
    nextManifest: nextManifest,
  );

  stdout.writeln(
    'IMPORTED: ${pack.id} (${pack.questions.length} questions)${command.activate ? ' and activated' : ''}',
  );
  stdout.writeln('Rebuild or restart the app to load the pack into SQLite.');
}

void _listPacks(String bankDirectory) {
  final bank = _loadBank(bankDirectory);
  stdout.writeln('Active pack: ${bank.manifest.activePackId}');
  if (bank.entries.isEmpty) {
    stdout.writeln('Imported packs: none');
    return;
  }
  for (final entry in bank.entries.values) {
    stdout.writeln(
      '- ${entry.pack.id}: ${entry.pack.questions.length} questions (${entry.pack.validationStatus.name}, ${entry.fileName})',
    );
  }
}

void _runSimilarity(_Command command) {
  final bank = _loadBank(command.bankDirectory);
  final entry = bank.entryFor(command.subject!);
  _ensureSimilaritySafe(
    entry.pack,
    bank.entries.values.map((candidate) => candidate.pack),
  );
  stdout.writeln(
    'SIMILARITY PASS: ${entry.pack.id} has no normalized prompt match at or above 0.82.',
  );
}

void _createReviewTemplate(_Command command) {
  final bank = _loadBank(command.bankDirectory);
  final entry = bank.entryFor(command.subject!);
  if (entry.pack.validationStatus != QuestionValidationStatus.draft) {
    throw const FormatException(
      'Review templates can only be created for draft packs.',
    );
  }
  _ensureReviewerId(command.reviewerId!, 'reviewer');
  _ensureSimilaritySafe(
    entry.pack,
    bank.entries.values.map((candidate) => candidate.pack),
  );
  final output = File(command.outputPath!);
  if (output.existsSync()) {
    throw FileSystemException('Review output already exists', output.path);
  }
  output.parent.createSync(recursive: true);
  final digest = const QuestionPackFingerprint().compute(entry.pack);
  final review = const QuestionReviewCodec().template(
    pack: entry.pack,
    reviewerId: command.reviewerId!,
    contentSha256: digest,
  );
  output.writeAsStringSync(const QuestionReviewCodec().encode(review));
  stdout.writeln('REVIEW TEMPLATE: ${output.path}');
  stdout.writeln('Complete every field and checklist item before promotion.');
}

void _promotePack(_Command command) {
  final bank = _loadBank(command.bankDirectory);
  final entry = bank.entryFor(command.subject!);
  _ensureSimilaritySafe(
    entry.pack,
    bank.entries.values.map((candidate) => candidate.pack),
  );

  late final QuestionPack promoted;
  final target = command.targetStatus!;
  if (target == QuestionValidationStatus.validated) {
    final reviewFile = File(command.reviewPath!);
    if (!reviewFile.existsSync()) {
      throw FileSystemException('Review file does not exist', reviewFile.path);
    }
    final submission = const QuestionReviewCodec().decode(
      reviewFile.readAsStringSync(),
    );
    final digest = const QuestionPackFingerprint().compute(entry.pack);
    final evidence = const QuestionReviewCodec().approve(
      submission: submission,
      pack: entry.pack,
      contentSha256: digest,
    );
    promoted = const QuestionPackPromotionService().validateDraft(
      entry.pack,
      evidence,
    );
  } else {
    _ensureReviewerId(command.publisherId!, 'publisher');
    promoted = const QuestionPackPromotionService().publishValidated(
      entry.pack,
      publisherId: command.publisherId!,
      publishedAt: DateTime.now().toUtc(),
    );
  }

  final destination = File(
    '${bank.directory.path}/${promoted.id}.${promoted.validationStatus.name}.json',
  );
  if (destination.existsSync()) {
    throw FileSystemException(
      'Immutable promotion artifact already exists',
      destination.path,
    );
  }
  final currentIndex = bank.manifest.packFiles.indexOf(entry.fileName);
  final nextFiles = [...bank.manifest.packFiles];
  nextFiles[currentIndex] = destination.uri.pathSegments.last;
  final nextManifest = QuestionBankManifest(
    activePackId: bank.manifest.activePackId,
    packFiles: List.unmodifiable(nextFiles),
  );
  _writePackAndManifest(
    pack: promoted,
    destination: destination,
    manifestFile: bank.manifestFile,
    nextManifest: nextManifest,
  );
  stdout.writeln(
    'PROMOTED: ${promoted.id} → ${promoted.validationStatus.name}',
  );
  stdout.writeln('Previous lifecycle artifact retained: ${entry.fileName}');
}

void _ensureSimilaritySafe(QuestionPack pack, Iterable<QuestionPack> existing) {
  final report = const QuestionSimilarityAnalyzer().analyze(
    target: pack,
    existingPacks: existing,
  );
  if (!report.hasBlockingMatches) {
    return;
  }
  final details = report.matches
      .map(
        (match) =>
            '${match.questionId} ↔ ${match.comparedPackId}/${match.comparedQuestionId} '
            '(${match.exactNormalizedMatch ? 'exact' : match.score.toStringAsFixed(3)})',
      )
      .join('; ');
  throw FormatException(
    'Similarity gate failed at threshold ${report.threshold}: $details. '
    'Revise the draft using a new version and immutable IDs.',
  );
}

_LoadedBank _loadBank(String bankDirectory) {
  final directory = Directory(bankDirectory);
  final manifestFile = File('${directory.path}/manifest.json');
  if (!manifestFile.existsSync()) {
    throw FileSystemException(
      'Bank manifest does not exist',
      manifestFile.path,
    );
  }
  final manifest = QuestionBankManifest.decode(manifestFile.readAsStringSync());
  final entries = <String, _BankEntry>{};
  for (final fileName in manifest.packFiles) {
    final pack = _readPack('${directory.path}/$fileName');
    if (entries.containsKey(pack.id)) {
      throw FormatException('Duplicate pack ID ${pack.id} in bank manifest.');
    }
    entries[pack.id] = _BankEntry(fileName: fileName, pack: pack);
  }
  return _LoadedBank(
    directory: directory,
    manifestFile: manifestFile,
    manifest: manifest,
    entries: entries,
  );
}

void _writePackAndManifest({
  required QuestionPack pack,
  required File destination,
  required File manifestFile,
  required QuestionBankManifest nextManifest,
}) {
  final packTemporary = File('${destination.path}.tmp');
  final manifestTemporary = File('${manifestFile.path}.tmp');
  var destinationCreated = false;
  try {
    packTemporary.writeAsStringSync(const QuestionPackCodec().encode(pack));
    manifestTemporary.writeAsStringSync(nextManifest.encode());
    packTemporary.renameSync(destination.path);
    destinationCreated = true;
    manifestTemporary.renameSync(manifestFile.path);
  } on Object {
    if (packTemporary.existsSync()) {
      packTemporary.deleteSync();
    }
    if (manifestTemporary.existsSync()) {
      manifestTemporary.deleteSync();
    }
    if (destinationCreated && destination.existsSync()) {
      destination.deleteSync();
    }
    rethrow;
  }
}

void _ensureReviewerId(String value, String label) {
  if (!RegExp(r'^[a-z0-9]+(?:_[a-z0-9]+)*$').hasMatch(value) ||
      value.length > 128) {
    throw FormatException('$label must be lowercase snake_case.');
  }
}

class _LoadedBank {
  const _LoadedBank({
    required this.directory,
    required this.manifestFile,
    required this.manifest,
    required this.entries,
  });

  final Directory directory;
  final File manifestFile;
  final QuestionBankManifest manifest;
  final Map<String, _BankEntry> entries;

  _BankEntry entryFor(String packId) {
    final entry = entries[packId];
    if (entry == null) {
      throw FormatException('Pack ID $packId is not in the bank manifest.');
    }
    return entry;
  }
}

class _BankEntry {
  const _BankEntry({required this.fileName, required this.pack});

  final String fileName;
  final QuestionPack pack;
}

class _Command {
  const _Command({
    required this.name,
    required this.subject,
    required this.activate,
    required this.bankDirectory,
    required this.reviewerId,
    required this.publisherId,
    required this.reviewPath,
    required this.outputPath,
    required this.targetStatus,
  });

  final String name;
  final String? subject;
  final bool activate;
  final String bankDirectory;
  final String? reviewerId;
  final String? publisherId;
  final String? reviewPath;
  final String? outputPath;
  final QuestionValidationStatus? targetStatus;

  static _Command parse(List<String> arguments) {
    if (arguments.isEmpty || arguments.contains('--help')) {
      _printUsage(stdout);
      exit(0);
    }
    final name = arguments.first;
    if (!const {
      'validate',
      'import',
      'list',
      'similarity',
      'review-template',
      'promote',
    }.contains(name)) {
      throw _UsageException('Unknown command $name.');
    }

    String? subject;
    var activate = false;
    var bankDirectory = _defaultBankDirectory;
    String? reviewerId;
    String? publisherId;
    String? reviewPath;
    String? outputPath;
    QuestionValidationStatus? targetStatus;
    for (var index = 1; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument == '--activate') {
        activate = true;
      } else if (const {
        '--bank-dir',
        '--reviewer',
        '--publisher',
        '--review',
        '--output',
        '--to',
      }.contains(argument)) {
        if (index + 1 >= arguments.length) {
          throw _UsageException('$argument requires a value.');
        }
        final value = arguments[++index];
        switch (argument) {
          case '--bank-dir':
            bankDirectory = value;
            break;
          case '--reviewer':
            reviewerId = value;
            break;
          case '--publisher':
            publisherId = value;
            break;
          case '--review':
            reviewPath = value;
            break;
          case '--output':
            outputPath = value;
            break;
          case '--to':
            if (value == 'validated') {
              targetStatus = QuestionValidationStatus.validated;
            } else if (value == 'published') {
              targetStatus = QuestionValidationStatus.published;
            } else {
              throw const _UsageException(
                '--to must be validated or published.',
              );
            }
            break;
        }
      } else if (argument.startsWith('--')) {
        throw _UsageException('Unknown option $argument.');
      } else if (subject == null) {
        subject = argument;
      } else {
        throw const _UsageException('Too many positional arguments.');
      }
    }

    if (name == 'list' && subject != null) {
      throw const _UsageException('list does not accept a subject.');
    }
    if (name != 'list' && subject == null) {
      throw _UsageException('$name requires a file path or pack ID.');
    }
    if (name != 'import' && activate) {
      throw const _UsageException('--activate is only valid with import.');
    }
    if (name == 'review-template' &&
        (reviewerId == null || outputPath == null)) {
      throw const _UsageException(
        'review-template requires --reviewer and --output.',
      );
    }
    if (name == 'promote') {
      if (targetStatus == null) {
        throw const _UsageException('promote requires --to.');
      }
      if (targetStatus == QuestionValidationStatus.validated &&
          reviewPath == null) {
        throw const _UsageException(
          'Promotion to validated requires --review.',
        );
      }
      if (targetStatus == QuestionValidationStatus.published &&
          publisherId == null) {
        throw const _UsageException(
          'Promotion to published requires --publisher.',
        );
      }
    }
    return _Command(
      name: name,
      subject: subject,
      activate: activate,
      bankDirectory: bankDirectory,
      reviewerId: reviewerId,
      publisherId: publisherId,
      reviewPath: reviewPath,
      outputPath: outputPath,
      targetStatus: targetStatus,
    );
  }
}

class _UsageException implements Exception {
  const _UsageException(this.message);

  final String message;
}

void _printUsage(IOSink output) {
  output.writeln('''
Question bank commands:
  dart run tool/question_bank.dart validate <pack.json>
  dart run tool/question_bank.dart import <draft.json> [--activate] [--bank-dir <path>]
  dart run tool/question_bank.dart list [--bank-dir <path>]
  dart run tool/question_bank.dart similarity <pack-id> [--bank-dir <path>]
  dart run tool/question_bank.dart review-template <pack-id> --reviewer <id> --output <review.json> [--bank-dir <path>]
  dart run tool/question_bank.dart promote <pack-id> --to validated --review <review.json> [--bank-dir <path>]
  dart run tool/question_bank.dart promote <pack-id> --to published --publisher <id> [--bank-dir <path>]
''');
}
