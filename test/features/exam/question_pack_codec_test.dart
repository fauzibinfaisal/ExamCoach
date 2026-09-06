import 'dart:convert';
import 'dart:io';

import 'package:exam_coach/features/exam/data/bundled_question_bank_loader.dart';
import 'package:exam_coach/features/exam/data/question_bank_manifest.dart';
import 'package:exam_coach/features/exam/data/question_pack_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String validSource;

  setUpAll(() {
    validSource = File(
      'content/examples/question_pack.example.json',
    ).readAsStringSync();
  });

  test('decodes a valid AI-generated draft pack', () {
    final pack = const QuestionPackCodec().decode(validSource);

    expect(pack.id, 'pack_cpns_tiu_ai_example_v1');
    expect(pack.questions, hasLength(6));
    expect(pack.tryoutQuestionIds, hasLength(6));
    expect(pack.generation.promptVersion, 'ai_question_pack_v1');
    expect(pack.validationStatus.name, 'draft');
    expect(pack.reviewer, isNull);
  });

  test('rejects an AI pack that claims to be validated', () {
    final source = jsonDecode(validSource) as Map<String, dynamic>;
    final metadata = source['pack'] as Map<String, dynamic>;
    metadata['validationStatus'] = 'validated';
    metadata['reviewer'] = 'ai_self_review';

    expect(
      () => const QuestionPackCodec().decode(jsonEncode(source)),
      throwsA(
        isA<QuestionPackValidationException>().having(
          (error) => error.issues.join(' '),
          'issues',
          contains('schemaVersion 1 accepts AI-generated draft'),
        ),
      ),
    );
  });

  test('reports broken answer and duplicate tryout references', () {
    final source = jsonDecode(validSource) as Map<String, dynamic>;
    final metadata = source['pack'] as Map<String, dynamic>;
    final tryoutIds = metadata['tryoutQuestionIds'] as List<dynamic>;
    tryoutIds[1] = tryoutIds.first;
    final questions = source['questions'] as List<dynamic>;
    final firstQuestion = questions.first as Map<String, dynamic>;
    firstQuestion['correctOptionId'] = 'missing';

    expect(
      () => const QuestionPackCodec().decode(jsonEncode(source)),
      throwsA(
        isA<QuestionPackValidationException>().having(
          (error) => error.issues.join(' '),
          'issues',
          allOf(
            contains('does not reference an option'),
            contains('duplicate'),
          ),
        ),
      ),
    );
  });

  test('manifest rejects path traversal', () {
    expect(
      () => QuestionBankManifest.decode(
        jsonEncode({
          'schemaVersion': 1,
          'activePackId': 'safe_pack_v1',
          'packs': ['../unsafe.json'],
        }),
      ),
      throwsFormatException,
    );
  });

  testWidgets('loads the bundled bank manifest', (tester) async {
    final bank = await BundledQuestionBankLoader().load();

    expect(bank.activePackId, 'pack_tiu_prototype_v1');
    expect(bank.packs, isEmpty);
  });
}
