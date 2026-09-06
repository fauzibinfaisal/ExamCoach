import 'dart:io';

import 'package:exam_coach/features/exam/data/question_bank_manifest.dart';
import 'package:exam_coach/features/exam/data/question_pack_codec.dart';
import 'package:exam_coach/features/exam/domain/models/question_pack.dart';

const _defaultBankDirectory = 'assets/question_bank';

Future<void> main(List<String> arguments) async {
  try {
    final command = _Command.parse(arguments);
    switch (command.name) {
      case 'validate':
        final pack = _readPack(command.inputPath!);
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
    }
  } on QuestionPackValidationException catch (error) {
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
  final pack = _readPack(command.inputPath!);
  final bankDirectory = Directory(command.bankDirectory);
  bankDirectory.createSync(recursive: true);
  final manifestFile = File('${bankDirectory.path}/manifest.json');
  if (!manifestFile.existsSync()) {
    throw FileSystemException(
      'Bank manifest does not exist',
      manifestFile.path,
    );
  }
  final manifest = QuestionBankManifest.decode(manifestFile.readAsStringSync());
  if (manifest.activePackId == pack.id) {
    throw FormatException('Pack ID ${pack.id} already exists in the bank.');
  }

  final existingPackIds = <String>{};
  final existingQuestionIds = <String>{};
  for (final fileName in manifest.packFiles) {
    final existing = _readPack('${bankDirectory.path}/$fileName');
    existingPackIds.add(existing.id);
    existingQuestionIds.addAll(
      existing.questions.map((question) => question.id),
    );
  }
  if (existingPackIds.contains(pack.id)) {
    throw FormatException('Pack ID ${pack.id} already exists in the bank.');
  }
  final duplicateQuestions = pack.questions
      .map((question) => question.id)
      .where(existingQuestionIds.contains)
      .toList();
  if (duplicateQuestions.isNotEmpty) {
    throw FormatException(
      'Question IDs already exist: ${duplicateQuestions.join(', ')}.',
    );
  }

  final fileName = '${pack.id}.json';
  final destination = File('${bankDirectory.path}/$fileName');
  if (destination.existsSync()) {
    throw FileSystemException('Destination already exists', destination.path);
  }

  final nextManifest = QuestionBankManifest(
    activePackId: command.activate ? pack.id : manifest.activePackId,
    packFiles: List.unmodifiable([...manifest.packFiles, fileName]),
  );
  final packTemporary = File('${destination.path}.tmp');
  final manifestTemporary = File('${manifestFile.path}.tmp');
  try {
    packTemporary.writeAsStringSync(const QuestionPackCodec().encode(pack));
    manifestTemporary.writeAsStringSync(nextManifest.encode());
    packTemporary.renameSync(destination.path);
    manifestTemporary.renameSync(manifestFile.path);
  } on Object {
    if (packTemporary.existsSync()) {
      packTemporary.deleteSync();
    }
    if (manifestTemporary.existsSync()) {
      manifestTemporary.deleteSync();
    }
    if (destination.existsSync() && !manifest.packFiles.contains(fileName)) {
      destination.deleteSync();
    }
    rethrow;
  }

  stdout.writeln(
    'IMPORTED: ${pack.id} (${pack.questions.length} questions)${command.activate ? ' and activated' : ''}',
  );
  stdout.writeln('Rebuild or restart the app to load the pack into SQLite.');
}

void _listPacks(String bankDirectory) {
  final manifestFile = File('$bankDirectory/manifest.json');
  if (!manifestFile.existsSync()) {
    throw FileSystemException(
      'Bank manifest does not exist',
      manifestFile.path,
    );
  }
  final manifest = QuestionBankManifest.decode(manifestFile.readAsStringSync());
  stdout.writeln('Active pack: ${manifest.activePackId}');
  if (manifest.packFiles.isEmpty) {
    stdout.writeln('Imported AI packs: none');
    return;
  }
  for (final fileName in manifest.packFiles) {
    final pack = _readPack('$bankDirectory/$fileName');
    stdout.writeln(
      '- ${pack.id}: ${pack.questions.length} questions (${pack.validationStatus.name})',
    );
  }
}

class _Command {
  const _Command({
    required this.name,
    required this.inputPath,
    required this.activate,
    required this.bankDirectory,
  });

  final String name;
  final String? inputPath;
  final bool activate;
  final String bankDirectory;

  static _Command parse(List<String> arguments) {
    if (arguments.isEmpty || arguments.contains('--help')) {
      _printUsage(stdout);
      exit(0);
    }
    final name = arguments.first;
    if (!const {'validate', 'import', 'list'}.contains(name)) {
      throw _UsageException('Unknown command $name.');
    }

    String? inputPath;
    var activate = false;
    var bankDirectory = _defaultBankDirectory;
    for (var index = 1; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument == '--activate') {
        activate = true;
      } else if (argument == '--bank-dir') {
        if (index + 1 >= arguments.length) {
          throw const _UsageException('--bank-dir requires a path.');
        }
        bankDirectory = arguments[++index];
      } else if (argument.startsWith('--')) {
        throw _UsageException('Unknown option $argument.');
      } else if (inputPath == null) {
        inputPath = argument;
      } else {
        throw const _UsageException('Too many input paths.');
      }
    }

    if ((name == 'validate' || name == 'import') && inputPath == null) {
      throw _UsageException('$name requires a JSON file path.');
    }
    if (name == 'list' && inputPath != null) {
      throw const _UsageException('list does not accept an input file.');
    }
    if (name != 'import' && activate) {
      throw const _UsageException('--activate is only valid with import.');
    }
    return _Command(
      name: name,
      inputPath: inputPath,
      activate: activate,
      bankDirectory: bankDirectory,
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
  dart run tool/question_bank.dart import <pack.json> [--activate] [--bank-dir <path>]
  dart run tool/question_bank.dart list [--bank-dir <path>]
''');
}
