import 'package:exam_coach/features/exam/data/question_bank_manifest.dart';
import 'package:exam_coach/features/exam/data/question_pack_codec.dart';
import 'package:exam_coach/features/exam/domain/models/question_pack.dart';
import 'package:flutter/services.dart';

class BundledQuestionBank {
  const BundledQuestionBank({required this.activePackId, required this.packs});

  final String activePackId;
  final List<QuestionPack> packs;
}

class BundledQuestionBankLoader {
  BundledQuestionBankLoader({AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  static const assetDirectory = 'assets/question_bank';
  static const manifestAsset = '$assetDirectory/manifest.json';

  final AssetBundle _bundle;
  final QuestionPackCodec _codec = const QuestionPackCodec();

  Future<BundledQuestionBank> load() async {
    final manifest = QuestionBankManifest.decode(
      await _bundle.loadString(manifestAsset),
    );
    final packs = <QuestionPack>[];
    final packIds = <String>{};
    final questionIds = <String>{};

    for (final file in manifest.packFiles) {
      final pack = _codec.decode(
        await _bundle.loadString('$assetDirectory/$file'),
        sourceName: file,
      );
      if (!packIds.add(pack.id)) {
        throw FormatException('Duplicate bundled pack ID ${pack.id}.');
      }
      for (final question in pack.questions) {
        if (!questionIds.add(question.id)) {
          throw FormatException(
            'Duplicate bundled question ID ${question.id}.',
          );
        }
      }
      packs.add(pack);
    }

    return BundledQuestionBank(
      activePackId: manifest.activePackId,
      packs: List.unmodifiable(packs),
    );
  }
}
