import 'dart:io';

import 'package:exam_coach/features/exam/data/question_bank_manifest.dart';
import 'package:exam_coach/features/exam/data/question_pack_codec.dart';
import 'package:exam_coach/features/exam/data/question_review_codec.dart';
import 'package:exam_coach/features/exam/domain/models/question.dart';
import 'package:exam_coach/features/exam/domain/models/question_pack_review.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'exam_coach_content_cli_test_',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'CLI keeps immutable artifacts through review and publication',
    () async {
      final bankDirectory = Directory('${temporaryDirectory.path}/bank')
        ..createSync(recursive: true);
      final manifestFile = File('${bankDirectory.path}/manifest.json');
      manifestFile.writeAsStringSync(
        const QuestionBankManifest(
          activePackId: 'pack_tiu_prototype_v1',
          packFiles: [],
        ).encode(),
      );
      final sourcePath = File(
        'content/examples/question_pack.example.json',
      ).absolute.path;
      final importResult = await _runCli([
        'import',
        sourcePath,
        '--bank-dir',
        bankDirectory.path,
      ]);
      expect(importResult.exitCode, 0, reason: importResult.stderr as String?);

      const packId = 'pack_cpns_tiu_ai_example_v1';
      final draftFile = File('${bankDirectory.path}/$packId.json');
      final reviewFile = File('${temporaryDirectory.path}/review.json');
      final templateResult = await _runCli([
        'review-template',
        packId,
        '--reviewer',
        'reviewer_fauzi',
        '--output',
        reviewFile.path,
        '--bank-dir',
        bankDirectory.path,
      ]);
      expect(
        templateResult.exitCode,
        0,
        reason: templateResult.stderr as String?,
      );

      final incompleteResult = await _runCli([
        'promote',
        packId,
        '--to',
        'validated',
        '--review',
        reviewFile.path,
        '--bank-dir',
        bankDirectory.path,
      ]);
      expect(incompleteResult.exitCode, 65);
      expect(
        incompleteResult.stderr,
        contains('Question review is incomplete'),
      );

      final draft = const QuestionPackCodec().decode(
        draftFile.readAsStringSync(),
      );
      final template = const QuestionReviewCodec().decode(
        reviewFile.readAsStringSync(),
      );
      reviewFile.writeAsStringSync(
        const QuestionReviewCodec().encode(
          QuestionReviewSubmission(
            packId: template.packId,
            contentSha256: template.contentSha256,
            reviewerId: template.reviewerId,
            reviewedAt: draft.generation.generatedAt.add(
              const Duration(hours: 1),
            ),
            decision: QuestionReviewDecision.approved,
            notes: 'Review fixture menyetujui seluruh pemeriksaan untuk test.',
            provenanceDecision: QuestionProvenanceDecision.aiGeneratedOriginal,
            provenanceNotes:
                'Review fixture mengonfirmasi metadata sumber untuk test.',
            reviewedQuestionIds: template.reviewedQuestionIds,
            checks: {
              for (final criterion in QuestionReviewCriterion.values)
                criterion: true,
            },
          ),
        ),
      );

      final validationResult = await _runCli([
        'promote',
        packId,
        '--to',
        'validated',
        '--review',
        reviewFile.path,
        '--bank-dir',
        bankDirectory.path,
      ]);
      expect(
        validationResult.exitCode,
        0,
        reason: validationResult.stderr as String?,
      );
      final validatedFile = File(
        '${bankDirectory.path}/$packId.validated.json',
      );
      expect(draftFile.existsSync(), isTrue);
      expect(validatedFile.existsSync(), isTrue);

      final publicationResult = await _runCli([
        'promote',
        packId,
        '--to',
        'published',
        '--publisher',
        'publisher_fauzi',
        '--bank-dir',
        bankDirectory.path,
      ]);
      expect(
        publicationResult.exitCode,
        0,
        reason: publicationResult.stderr as String?,
      );
      final publishedFile = File(
        '${bankDirectory.path}/$packId.published.json',
      );
      expect(validatedFile.existsSync(), isTrue);
      expect(publishedFile.existsSync(), isTrue);
      final published = const QuestionPackCodec().decode(
        publishedFile.readAsStringSync(),
      );
      expect(published.validationStatus, QuestionValidationStatus.published);
      expect(published.publication?.publisherId, 'publisher_fauzi');

      final manifest = QuestionBankManifest.decode(
        manifestFile.readAsStringSync(),
      );
      expect(manifest.packFiles, ['$packId.published.json']);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<ProcessResult> _runCli(List<String> arguments) => Process.run('dart', [
  'run',
  'tool/question_bank.dart',
  ...arguments,
], workingDirectory: Directory.current.path);
