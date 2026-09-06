import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:exam_coach/features/exam/domain/models/question_pack.dart';

class QuestionPackFingerprint {
  const QuestionPackFingerprint();

  String compute(QuestionPack pack) {
    final canonical = jsonEncode({
      'id': pack.id,
      'title': pack.title,
      'examId': pack.examId,
      'testId': pack.testId,
      'version': pack.version,
      'author': pack.author,
      'generation': {
        'provider': pack.generation.provider,
        'model': pack.generation.model,
        'promptVersion': pack.generation.promptVersion,
        'generatedAt': pack.generation.generatedAt.toUtc().toIso8601String(),
      },
      'tryoutQuestionIds': pack.tryoutQuestionIds,
      'questions': [
        for (final question in pack.questions)
          {
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
            'explanation': question.explanation,
            'version': question.version,
          },
      ],
    });
    return sha256.convert(utf8.encode(canonical)).toString();
  }
}
