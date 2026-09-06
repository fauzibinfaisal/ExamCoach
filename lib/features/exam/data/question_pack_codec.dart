import 'dart:convert';

import 'package:exam_coach/features/exam/domain/models/question.dart';
import 'package:exam_coach/features/exam/domain/models/question_pack.dart';
import 'package:exam_coach/features/exam/domain/models/taxonomy_path.dart';

class QuestionPackValidationException implements Exception {
  const QuestionPackValidationException(this.issues);

  final List<String> issues;

  @override
  String toString() =>
      'Question pack validation failed:\n- ${issues.join('\n- ')}';
}

class QuestionPackCodec {
  const QuestionPackCodec();

  static const schemaVersion = 1;

  QuestionPack decode(String source, {String sourceName = 'question pack'}) {
    late final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw QuestionPackValidationException([
        '$sourceName is not valid JSON: ${error.message}',
      ]);
    }

    try {
      final root = _asObject(decoded, 'root');
      final version = _asInt(root['schemaVersion'], 'schemaVersion');
      if (version != schemaVersion) {
        throw FormatException(
          'schemaVersion must be $schemaVersion, received $version.',
        );
      }
      final metadata = _asObject(root['pack'], 'pack');
      final generation = _asObject(metadata['generation'], 'pack.generation');
      final rawQuestions = _asList(root['questions'], 'questions');

      final pack = QuestionPack(
        id: _asString(metadata['id'], 'pack.id'),
        title: _asString(metadata['title'], 'pack.title'),
        examId: _asString(metadata['examId'], 'pack.examId'),
        testId: _asString(metadata['testId'], 'pack.testId'),
        version: _asInt(metadata['version'], 'pack.version'),
        validationStatus: _status(
          metadata['validationStatus'],
          'pack.validationStatus',
        ),
        author: _asString(metadata['author'], 'pack.author'),
        reviewer: _asNullableString(metadata['reviewer'], 'pack.reviewer'),
        generation: QuestionPackGeneration(
          provider: _asString(
            generation['provider'],
            'pack.generation.provider',
          ),
          model: _asString(generation['model'], 'pack.generation.model'),
          promptVersion: _asString(
            generation['promptVersion'],
            'pack.generation.promptVersion',
          ),
          generatedAt: _asDateTime(
            generation['generatedAt'],
            'pack.generation.generatedAt',
          ),
        ),
        tryoutQuestionIds: List.unmodifiable(
          _asList(
            metadata['tryoutQuestionIds'],
            'pack.tryoutQuestionIds',
          ).indexed.map(
            (entry) =>
                _asString(entry.$2, 'pack.tryoutQuestionIds[${entry.$1}]'),
          ),
        ),
        questions: List.unmodifiable(
          rawQuestions.indexed.map(
            (entry) => _question(
              _asObject(entry.$2, 'questions[${entry.$1}]'),
              entry.$1,
            ),
          ),
        ),
      );

      final issues = validate(pack);
      if (issues.isNotEmpty) {
        throw QuestionPackValidationException(issues);
      }
      return pack;
    } on QuestionPackValidationException {
      rethrow;
    } on FormatException catch (error) {
      throw QuestionPackValidationException(['$sourceName: ${error.message}']);
    }
  }

  List<String> validate(QuestionPack pack) {
    final issues = <String>[];
    final idPattern = RegExp(r'^[a-z0-9]+(?:_[a-z0-9]+)*$');
    void checkId(String value, String path) {
      if (!idPattern.hasMatch(value) || value.length > 128) {
        issues.add(
          '$path must use lowercase snake_case with at most 128 characters.',
        );
      }
    }

    checkId(pack.id, 'pack.id');
    checkId(pack.examId, 'pack.examId');
    checkId(pack.testId, 'pack.testId');
    checkId(pack.author, 'pack.author');
    if (!pack.id.endsWith('_v${pack.version}')) {
      issues.add('pack.id must end with _v${pack.version}.');
    }
    if (pack.version < 1) {
      issues.add('pack.version must be at least 1.');
    }
    if (pack.validationStatus != QuestionValidationStatus.draft) {
      issues.add('AI-generated imports must remain draft until human review.');
    }
    if (pack.reviewer != null) {
      issues.add('pack.reviewer must be null while the pack is draft.');
    }
    if (!pack.generation.generatedAt.isUtc) {
      issues.add('pack.generation.generatedAt must include a UTC timezone.');
    }
    if (pack.generation.promptVersion != 'ai_question_pack_v1') {
      issues.add('pack.generation.promptVersion must be ai_question_pack_v1.');
    }
    if (pack.questions.length < 6) {
      issues.add('questions must contain at least 6 items.');
    }
    if (pack.questions.length > 500) {
      issues.add('questions must contain at most 500 items.');
    }
    if (pack.tryoutQuestionIds.length != 6) {
      issues.add('pack.tryoutQuestionIds must contain exactly 6 IDs.');
    }

    final questionIds = <String>{};
    for (var index = 0; index < pack.questions.length; index++) {
      final question = pack.questions[index];
      final path = 'questions[$index]';
      checkId(question.id, '$path.id');
      if (!questionIds.add(question.id)) {
        issues.add('$path.id duplicates ${question.id}.');
      }
      if (question.prompt.length < 20 || question.prompt.length > 2000) {
        issues.add('$path.prompt must contain 20–2000 characters.');
      }
      if (question.options.length < 2 || question.options.length > 6) {
        issues.add('$path.options must contain 2–6 choices.');
      }
      final optionIds = <String>{};
      final optionTexts = <String>{};
      for (
        var optionIndex = 0;
        optionIndex < question.options.length;
        optionIndex++
      ) {
        final option = question.options[optionIndex];
        checkId(option.id, '$path.options[$optionIndex].id');
        if (!optionIds.add(option.id)) {
          issues.add('$path.options[$optionIndex].id is duplicated.');
        }
        if (!optionTexts.add(option.text.toLowerCase())) {
          issues.add('$path.options[$optionIndex].text is duplicated.');
        }
        if (option.text.length > 500) {
          issues.add(
            '$path.options[$optionIndex].text exceeds 500 characters.',
          );
        }
      }
      if (!optionIds.contains(question.correctOptionId)) {
        issues.add('$path.correctOptionId does not reference an option.');
      }
      if (!question.provenance.startsWith('ai_generated')) {
        issues.add('$path.provenance must identify AI-generated content.');
      }
      if (question.taxonomy.examId != pack.examId ||
          question.taxonomy.testId != pack.testId) {
        issues.add('$path taxonomy exam/test must match the pack.');
      }
      for (final entry in {
        '$path.taxonomy.examId': question.taxonomy.examId,
        '$path.taxonomy.testId': question.taxonomy.testId,
        '$path.taxonomy.domainId': question.taxonomy.domainId,
        '$path.taxonomy.topicId': question.taxonomy.topicId,
        '$path.taxonomy.subtopicId': question.taxonomy.subtopicId,
        '$path.taxonomy.skillId': question.taxonomy.skillId,
        '$path.taxonomy.microSkillId': question.taxonomy.microSkillId,
      }.entries) {
        checkId(entry.value, entry.key);
      }
      if (question.estimatedTime.inSeconds < 10 ||
          question.estimatedTime.inSeconds > 600) {
        issues.add('$path.estimatedTimeSeconds must be between 10 and 600.');
      }
      if (question.explanation.length < 20 ||
          question.explanation.length > 4000) {
        issues.add('$path.explanation must contain 20–4000 characters.');
      }
      if (question.validationStatus != pack.validationStatus) {
        issues.add('$path.validationStatus must match the pack.');
      }
      if (question.version < 1) {
        issues.add('$path.version must be at least 1.');
      }
      if (question.author != pack.author) {
        issues.add('$path.author must match pack.author.');
      }
      if (question.reviewer != pack.reviewer) {
        issues.add('$path.reviewer must match pack.reviewer.');
      }
    }

    final tryoutIds = <String>{};
    for (final id in pack.tryoutQuestionIds) {
      if (!tryoutIds.add(id)) {
        issues.add('pack.tryoutQuestionIds contains duplicate $id.');
      }
      if (!questionIds.contains(id)) {
        issues.add('pack.tryoutQuestionIds references unknown question $id.');
      }
    }
    return List.unmodifiable(issues);
  }

  String encode(QuestionPack pack) {
    final issues = validate(pack);
    if (issues.isNotEmpty) {
      throw QuestionPackValidationException(issues);
    }
    const encoder = JsonEncoder.withIndent('  ');
    return '${encoder.convert({
      'schemaVersion': schemaVersion,
      'pack': {
        'id': pack.id,
        'title': pack.title,
        'examId': pack.examId,
        'testId': pack.testId,
        'version': pack.version,
        'validationStatus': pack.validationStatus.name,
        'author': pack.author,
        'reviewer': pack.reviewer,
        'generation': {'provider': pack.generation.provider, 'model': pack.generation.model, 'promptVersion': pack.generation.promptVersion, 'generatedAt': pack.generation.generatedAt.toIso8601String()},
        'tryoutQuestionIds': pack.tryoutQuestionIds,
      },
      'questions': [for (final question in pack.questions) _questionToJson(question)],
    })}\n';
  }

  Question _question(Map<String, Object?> value, int index) {
    final path = 'questions[$index]';
    final taxonomy = _asObject(value['taxonomy'], '$path.taxonomy');
    final rawOptions = _asList(value['options'], '$path.options');
    return Question(
      id: _asString(value['id'], '$path.id'),
      prompt: _asString(value['prompt'], '$path.prompt'),
      options: List.unmodifiable(
        rawOptions.indexed.map((entry) {
          final optionPath = '$path.options[${entry.$1}]';
          final option = _asObject(entry.$2, optionPath);
          return QuestionOption(
            id: _asString(option['id'], '$optionPath.id'),
            text: _asString(option['text'], '$optionPath.text'),
          );
        }),
      ),
      correctOptionId: _asString(
        value['correctOptionId'],
        '$path.correctOptionId',
      ),
      taxonomy: TaxonomyPath(
        examId: _asString(taxonomy['examId'], '$path.taxonomy.examId'),
        testId: _asString(taxonomy['testId'], '$path.taxonomy.testId'),
        domainId: _asString(taxonomy['domainId'], '$path.taxonomy.domainId'),
        topicId: _asString(taxonomy['topicId'], '$path.taxonomy.topicId'),
        subtopicId: _asString(
          taxonomy['subtopicId'],
          '$path.taxonomy.subtopicId',
        ),
        skillId: _asString(taxonomy['skillId'], '$path.taxonomy.skillId'),
        microSkillId: _asString(
          taxonomy['microSkillId'],
          '$path.taxonomy.microSkillId',
        ),
        topicLabel: _asString(
          taxonomy['topicLabel'],
          '$path.taxonomy.topicLabel',
        ),
      ),
      difficulty: _difficulty(value['difficulty'], '$path.difficulty'),
      cognitiveType: _asString(value['cognitiveType'], '$path.cognitiveType'),
      estimatedTime: Duration(
        seconds: _asInt(
          value['estimatedTimeSeconds'],
          '$path.estimatedTimeSeconds',
        ),
      ),
      trapType: _asString(value['trapType'], '$path.trapType'),
      provenance: _asString(value['provenance'], '$path.provenance'),
      author: _asString(value['author'], '$path.author'),
      reviewer: _asNullableString(value['reviewer'], '$path.reviewer'),
      explanation: _asString(value['explanation'], '$path.explanation'),
      validationStatus: _status(
        value['validationStatus'],
        '$path.validationStatus',
      ),
      version: _asInt(value['version'], '$path.version'),
    );
  }
}

Map<String, Object?> _questionToJson(Question question) => {
  'id': question.id,
  'prompt': question.prompt,
  'options': [
    for (final option in question.options)
      {'id': option.id, 'text': option.text},
  ],
  'correctOptionId': question.correctOptionId,
  'taxonomy': {
    'examId': question.taxonomy.examId,
    'testId': question.taxonomy.testId,
    'domainId': question.taxonomy.domainId,
    'topicId': question.taxonomy.topicId,
    'subtopicId': question.taxonomy.subtopicId,
    'skillId': question.taxonomy.skillId,
    'microSkillId': question.taxonomy.microSkillId,
    'topicLabel': question.taxonomy.topicLabel,
  },
  'difficulty': question.difficulty.name,
  'cognitiveType': question.cognitiveType,
  'estimatedTimeSeconds': question.estimatedTime.inSeconds,
  'trapType': question.trapType,
  'provenance': question.provenance,
  'author': question.author,
  'reviewer': question.reviewer,
  'explanation': question.explanation,
  'validationStatus': question.validationStatus.name,
  'version': question.version,
};

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

String? _asNullableString(Object? value, String path) {
  if (value == null) {
    return null;
  }
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$path must be null or a non-empty string.');
  }
  return value.trim();
}

int _asInt(Object? value, String path) {
  if (value is! int) {
    throw FormatException('$path must be an integer.');
  }
  return value;
}

DateTime _asDateTime(Object? value, String path) {
  final source = _asString(value, path);
  final parsed = DateTime.tryParse(source);
  if (parsed == null) {
    throw FormatException('$path must be an ISO-8601 timestamp.');
  }
  return parsed;
}

QuestionDifficulty _difficulty(Object? value, String path) {
  final name = _asString(value, path);
  try {
    return QuestionDifficulty.values.byName(name);
  } on ArgumentError {
    throw FormatException('$path must be easy, medium, or hard.');
  }
}

QuestionValidationStatus _status(Object? value, String path) {
  final name = _asString(value, path);
  try {
    return QuestionValidationStatus.values.byName(name);
  } on ArgumentError {
    throw FormatException('$path must be draft, validated, or retired.');
  }
}
