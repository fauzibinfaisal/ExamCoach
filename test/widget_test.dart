import 'package:exam_coach/app/app.dart';
import 'package:exam_coach/features/exam/data/mock_question_repository.dart';
import 'package:exam_coach/features/learning/application/learning_flow_cubit.dart';
import 'package:exam_coach/learning_engine/adaptive_drill_engine.dart';
import 'package:exam_coach/learning_engine/recommendation_engine.dart';
import 'package:exam_coach/learning_engine/scoring_engine.dart';
import 'package:exam_coach/learning_engine/weakness_analyzer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('completes tryout, drill, and updated insight', (tester) async {
    final cubit = LearningFlowCubit(
      questionRepository: MockQuestionRepository(),
      scoringEngine: const ScoringEngine(),
      weaknessAnalyzer: const WeaknessAnalyzer(),
      recommendationEngine: const RecommendationEngine(),
      adaptiveDrillEngine: const AdaptiveDrillEngine(),
    );
    await tester.pumpWidget(ExamCoachApp(learningFlowCubit: cubit));

    expect(
      find.text('Belajar dengan arah,\nbukan sekadar banyak soal.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('start-tryout-button')));
    await tester.pumpAndSettle();

    expect(find.text('Ringkasan tryout'), findsOneWidget);
    expect(find.text('6 soal untuk membaca pola awalmu'), findsOneWidget);
    await tester.tap(find.byKey(const Key('begin-session-button')));
    await tester.pumpAndSettle();

    for (var index = 0; index < 6; index++) {
      await tester.tap(find.byKey(const Key('answer-a')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('submit-answer-button')));
      await tester.pumpAndSettle();
    }

    expect(find.text('Tryout selesai'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('start-drill-button')),
      300,
    );
    expect(find.text('Rekomendasi berikutnya'), findsOneWidget);
    expect(find.byKey(const Key('start-drill-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('start-drill-button')));
    await tester.pumpAndSettle();

    expect(find.text('DRILL ADAPTIF'), findsOneWidget);
    expect(find.text('1/6'), findsOneWidget);

    for (var index = 0; index < 6; index++) {
      await tester.tap(find.byKey(const Key('answer-a')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('submit-answer-button')));
      await tester.pumpAndSettle();
    }

    expect(find.text('Insight diperbarui'), findsOneWidget);
    expect(
      find.text('Jawaban drill sudah masuk ke profil performamu.'),
      findsOneWidget,
    );
  });
}
