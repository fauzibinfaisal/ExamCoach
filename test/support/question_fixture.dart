import 'package:exam_coach/features/exam/domain/models/question.dart';
import 'package:exam_coach/features/exam/domain/models/taxonomy_path.dart';

Question questionFixture({
  required String id,
  String topicId = 'topic_ratio',
  String topicLabel = 'Ratio',
  String correctOptionId = 'a',
  QuestionDifficulty difficulty = QuestionDifficulty.medium,
  Duration estimatedTime = const Duration(seconds: 60),
}) {
  return Question(
    id: id,
    prompt: 'Question $id',
    options: const [
      QuestionOption(id: 'a', text: 'A'),
      QuestionOption(id: 'b', text: 'B'),
    ],
    correctOptionId: correctOptionId,
    taxonomy: TaxonomyPath(
      examId: 'exam_generic',
      testId: 'test_generic',
      domainId: 'domain_reasoning',
      topicId: topicId,
      subtopicId: 'sub_$topicId',
      skillId: 'skill_$topicId',
      microSkillId: 'micro_$topicId',
      topicLabel: topicLabel,
    ),
    difficulty: difficulty,
    cognitiveType: 'reasoning',
    estimatedTime: estimatedTime,
    trapType: 'none',
    provenance: 'test_fixture',
    explanation: 'Fixture explanation',
    validationStatus: QuestionValidationStatus.draft,
    version: 1,
  );
}
