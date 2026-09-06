import 'dart:convert';

class QuestionBankManifest {
  const QuestionBankManifest({
    required this.activePackId,
    required this.packFiles,
  });

  static const schemaVersion = 1;

  final String activePackId;
  final List<String> packFiles;

  factory QuestionBankManifest.decode(String source) {
    late final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('Invalid bank manifest JSON: ${error.message}');
    }
    final root = _asObject(decoded, 'manifest');
    final version = _asInt(root['schemaVersion'], 'manifest.schemaVersion');
    if (version != schemaVersion) {
      throw FormatException(
        'Unsupported bank manifest schemaVersion $version; expected $schemaVersion.',
      );
    }

    final activePackId = _asString(
      root['activePackId'],
      'manifest.activePackId',
    );
    final rawFiles = _asList(root['packs'], 'manifest.packs');
    final files = <String>[];
    for (var index = 0; index < rawFiles.length; index++) {
      final file = _asString(rawFiles[index], 'manifest.packs[$index]');
      if (file.contains('/') ||
          file.contains('\\') ||
          file.contains('..') ||
          !file.endsWith('.json')) {
        throw FormatException(
          'manifest.packs[$index] must be a plain .json filename.',
        );
      }
      if (files.contains(file)) {
        throw FormatException('Duplicate pack file in manifest: $file.');
      }
      files.add(file);
    }

    return QuestionBankManifest(
      activePackId: activePackId,
      packFiles: List.unmodifiable(files),
    );
  }

  String encode() {
    const encoder = JsonEncoder.withIndent('  ');
    return '${encoder.convert({'schemaVersion': schemaVersion, 'activePackId': activePackId, 'packs': packFiles})}\n';
  }
}

Map<String, Object?> _asObject(Object? value, String path) {
  if (value is! Map) {
    throw FormatException('$path must be a JSON object.');
  }
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<Object?> _asList(Object? value, String path) {
  if (value is! List) {
    throw FormatException('$path must be a JSON array.');
  }
  return value;
}

String _asString(Object? value, String path) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$path must be a non-empty string.');
  }
  return value.trim();
}

int _asInt(Object? value, String path) {
  if (value is! int) {
    throw FormatException('$path must be an integer.');
  }
  return value;
}
