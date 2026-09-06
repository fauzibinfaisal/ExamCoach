import 'dart:convert';

import 'package:exam_coach/features/exam/data/question_pack_fingerprint.dart';
import 'package:exam_coach/features/exam/domain/models/question.dart';
import 'package:exam_coach/features/exam/domain/models/question_pack.dart';
import 'package:exam_coach/features/exam/domain/models/taxonomy_path.dart';
import 'package:exam_coach/features/exam/domain/repositories/question_repository.dart';
import 'package:exam_coach/services/database/exam_coach_database.dart';
import 'package:sqflite/sqflite.dart';

class LocalQuestionRepository implements QuestionRepository {
  LocalQuestionRepository(this._database);

  static const prototypePackId = 'pack_tiu_prototype_v1';
  static const _initialTryoutIds = [
    'q_ratio_01',
    'q_ratio_02',
    'q_sequence_01',
    'q_sequence_02',
    'q_analogy_01',
    'q_analogy_02',
  ];

  final ExamCoachDatabase _database;
  List<Question> _questions = const [];
  String _activePackId = prototypePackId;
  List<String> _activeTryoutIds = _initialTryoutIds;

  Future<void> initializeWithSeed(
    QuestionRepository seed, {
    List<QuestionPack> importedPacks = const [],
    String activePackId = prototypePackId,
  }) async {
    final database = await _database.instance;
    final existing = await database.query(
      'question_packs',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: const [prototypePackId],
      limit: 1,
    );
    if (existing.isEmpty) {
      await _seed(database, seed.allQuestions);
    }
    for (final pack in importedPacks) {
      await _import(database, pack);
    }

    _activePackId = activePackId;
    if (activePackId == prototypePackId) {
      _activeTryoutIds = _initialTryoutIds;
    } else {
      final activePack = importedPacks.where((pack) => pack.id == activePackId);
      if (activePack.isEmpty) {
        throw StateError('Active question pack $activePackId is not bundled.');
      }
      _activeTryoutIds = activePack.single.tryoutQuestionIds;
    }
    await _load(database);
    if (initialTryoutQuestions.length != _activeTryoutIds.length) {
      throw StateError(
        'Active pack $_activePackId is missing one or more tryout questions.',
      );
    }
  }

  @override
  List<Question> get allQuestions => _questions;

  @override
  List<Question> get initialTryoutQuestions {
    final byId = {for (final question in _questions) question.id: question};
    return List.unmodifiable([for (final id in _activeTryoutIds) ?byId[id]]);
  }

  Future<void> _seed(Database database, List<Question> questions) async {
    if (questions.isEmpty) {
      throw StateError('Cannot seed an empty question pack.');
    }
    final first = questions.first;
    final now = DateTime.now().toUtc().toIso8601String();
    await database.transaction((transaction) async {
      await transaction.insert('question_packs', {
        'id': prototypePackId,
        'title': 'Diagnostic TIU Prototype',
        'exam_id': first.taxonomy.examId,
        'test_id': first.taxonomy.testId,
        'version': 1,
        'validation_status': QuestionValidationStatus.draft.name,
        'author': 'examcoach_development_team',
        'reviewer': null,
        'generator_provider': null,
        'generator_model': null,
        'prompt_version': null,
        'generated_at': null,
        'tryout_question_ids_json': jsonEncode(_initialTryoutIds),
        'downloaded_at': now,
      });
      for (var position = 0; position < questions.length; position++) {
        await transaction.insert(
          'questions',
          _questionToRow(questions[position], position, prototypePackId),
        );
      }
    });
  }

  Future<void> _import(Database database, QuestionPack pack) async {
    final existing = await database.query(
      'question_packs',
      where: 'id = ?',
      whereArgs: [pack.id],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      await _applyLifecycleUpdate(database, existing.single, pack);
      return;
    }

    final now = DateTime.now().toUtc().toIso8601String();
    await database.transaction((transaction) async {
      await transaction.insert('question_packs', {
        'id': pack.id,
        'title': pack.title,
        'exam_id': pack.examId,
        'test_id': pack.testId,
        'version': pack.version,
        'validation_status': pack.validationStatus.name,
        'author': pack.author,
        'reviewer': pack.reviewer,
        'generator_provider': pack.generation.provider,
        'generator_model': pack.generation.model,
        'prompt_version': pack.generation.promptVersion,
        'generated_at': pack.generation.generatedAt.toIso8601String(),
        'reviewed_at': pack.review?.reviewedAt.toIso8601String(),
        'review_notes': pack.review?.notes,
        'provenance_decision': pack.review?.provenanceDecision.name,
        'provenance_notes': pack.review?.provenanceNotes,
        'content_sha256': const QuestionPackFingerprint().compute(pack),
        'review_checklist_json': pack.review == null
            ? null
            : _reviewChecklistJson(pack),
        'publisher': pack.publication?.publisherId,
        'published_at': pack.publication?.publishedAt.toIso8601String(),
        'tryout_question_ids_json': jsonEncode(pack.tryoutQuestionIds),
        'downloaded_at': now,
      });
      for (var position = 0; position < pack.questions.length; position++) {
        await transaction.insert(
          'questions',
          _questionToRow(pack.questions[position], position, pack.id),
        );
      }
    });
  }

  Future<void> _applyLifecycleUpdate(
    Database database,
    Map<String, Object?> existingRow,
    QuestionPack incoming,
  ) async {
    final stored = await _storedPack(database, existingRow);
    const fingerprint = QuestionPackFingerprint();
    final storedDigest = fingerprint.compute(stored);
    final incomingDigest = fingerprint.compute(incoming);
    if (storedDigest != incomingDigest) {
      throw StateError(
        'Pack ${incoming.id} changed immutable content without new IDs.',
      );
    }
    final currentStatus = stored.validationStatus;
    final incomingStatus = incoming.validationStatus;
    if (currentStatus == incomingStatus) {
      return;
    }
    if (_lifecycleRank(incomingStatus) <= _lifecycleRank(currentStatus) ||
        incomingStatus == QuestionValidationStatus.retired) {
      throw StateError(
        'Pack ${incoming.id} cannot move from ${currentStatus.name} '
        'to ${incomingStatus.name}.',
      );
    }
    if (incoming.review == null) {
      throw StateError(
        'Pack ${incoming.id} requires persisted human review evidence.',
      );
    }
    await database.transaction((transaction) async {
      await transaction.update(
        'question_packs',
        {
          'validation_status': incomingStatus.name,
          'reviewer': incoming.reviewer,
          'reviewed_at': incoming.review!.reviewedAt.toIso8601String(),
          'review_notes': incoming.review!.notes,
          'provenance_decision': incoming.review!.provenanceDecision.name,
          'provenance_notes': incoming.review!.provenanceNotes,
          'content_sha256': incomingDigest,
          'review_checklist_json': _reviewChecklistJson(incoming),
          'publisher': incoming.publication?.publisherId,
          'published_at': incoming.publication?.publishedAt.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [incoming.id],
      );
      await transaction.update(
        'questions',
        {
          'validation_status': incomingStatus.name,
          'reviewer': incoming.reviewer,
        },
        where: 'pack_id = ?',
        whereArgs: [incoming.id],
      );
    });
  }

  Future<QuestionPack> _storedPack(
    Database database,
    Map<String, Object?> row,
  ) async {
    final provider = row['generator_provider'] as String?;
    final model = row['generator_model'] as String?;
    final promptVersion = row['prompt_version'] as String?;
    final generatedAt = row['generated_at'] as String?;
    if (provider == null ||
        model == null ||
        promptVersion == null ||
        generatedAt == null) {
      throw StateError(
        'Pack ${row['id']} is not an imported versioned AI pack.',
      );
    }
    final questionRows = await database.query(
      'questions',
      where: 'pack_id = ?',
      whereArgs: [row['id']],
      orderBy: 'position ASC',
    );
    return QuestionPack(
      id: row['id']! as String,
      title: row['title']! as String,
      examId: row['exam_id']! as String,
      testId: row['test_id']! as String,
      version: row['version']! as int,
      validationStatus: QuestionValidationStatus.values.byName(
        row['validation_status']! as String,
      ),
      author: row['author']! as String,
      reviewer: row['reviewer'] as String?,
      generation: QuestionPackGeneration(
        provider: provider,
        model: model,
        promptVersion: promptVersion,
        generatedAt: DateTime.parse(generatedAt),
      ),
      tryoutQuestionIds: List<String>.from(
        jsonDecode(row['tryout_question_ids_json']! as String) as List,
      ),
      questions: List.unmodifiable(questionRows.map(_questionFromRow)),
    );
  }

  static int _lifecycleRank(QuestionValidationStatus status) =>
      switch (status) {
        QuestionValidationStatus.draft => 0,
        QuestionValidationStatus.validated => 1,
        QuestionValidationStatus.published => 2,
        QuestionValidationStatus.retired => 3,
      };

  static String _reviewChecklistJson(QuestionPack pack) {
    final review = pack.review!;
    return jsonEncode({
      'reviewedQuestionIds': review.reviewedQuestionIds,
      'checks': {
        for (final entry in review.checks.entries) entry.key.name: entry.value,
      },
    });
  }

  Future<void> _load(Database database) async {
    final rows = await database.query(
      'questions',
      orderBy: 'pack_id ASC, position ASC',
    );
    _questions = List.unmodifiable(rows.map(_questionFromRow));
  }

  static Map<String, Object?> _questionToRow(
    Question question,
    int position,
    String packId,
  ) {
    return {
      'id': question.id,
      'pack_id': packId,
      'position': position,
      'prompt': question.prompt,
      'options_json': jsonEncode([
        for (final option in question.options)
          {'id': option.id, 'text': option.text},
      ]),
      'correct_option_id': question.correctOptionId,
      'exam_id': question.taxonomy.examId,
      'test_id': question.taxonomy.testId,
      'domain_id': question.taxonomy.domainId,
      'topic_id': question.taxonomy.topicId,
      'subtopic_id': question.taxonomy.subtopicId,
      'skill_id': question.taxonomy.skillId,
      'micro_skill_id': question.taxonomy.microSkillId,
      'topic_label': question.taxonomy.topicLabel,
      'difficulty': question.difficulty.name,
      'cognitive_type': question.cognitiveType,
      'estimated_time_ms': question.estimatedTime.inMilliseconds,
      'trap_type': question.trapType,
      'provenance': question.provenance,
      'author': question.author,
      'reviewer': question.reviewer,
      'explanation': question.explanation,
      'validation_status': question.validationStatus.name,
      'content_version': question.version,
    };
  }

  static Question _questionFromRow(Map<String, Object?> row) {
    final optionRows = jsonDecode(row['options_json']! as String) as List;
    return Question(
      id: row['id']! as String,
      prompt: row['prompt']! as String,
      options: List.unmodifiable(
        optionRows.map((value) {
          final option = value as Map<String, dynamic>;
          return QuestionOption(
            id: option['id']! as String,
            text: option['text']! as String,
          );
        }),
      ),
      correctOptionId: row['correct_option_id']! as String,
      taxonomy: TaxonomyPath(
        examId: row['exam_id']! as String,
        testId: row['test_id']! as String,
        domainId: row['domain_id']! as String,
        topicId: row['topic_id']! as String,
        subtopicId: row['subtopic_id']! as String,
        skillId: row['skill_id']! as String,
        microSkillId: row['micro_skill_id']! as String,
        topicLabel: row['topic_label']! as String,
      ),
      difficulty: QuestionDifficulty.values.byName(
        row['difficulty']! as String,
      ),
      cognitiveType: row['cognitive_type']! as String,
      estimatedTime: Duration(milliseconds: row['estimated_time_ms']! as int),
      trapType: row['trap_type']! as String,
      provenance: row['provenance']! as String,
      author: row['author']! as String,
      reviewer: row['reviewer'] as String?,
      explanation: row['explanation']! as String,
      validationStatus: QuestionValidationStatus.values.byName(
        row['validation_status']! as String,
      ),
      version: row['content_version']! as int,
    );
  }
}
