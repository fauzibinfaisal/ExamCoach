import 'package:exam_coach/features/exam/domain/models/answer_record.dart';
import 'package:exam_coach/features/exam/domain/models/question.dart';
import 'package:exam_coach/features/learning/application/learning_flow_cubit.dart';
import 'package:exam_coach/features/learning/application/learning_flow_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class AnswerReviewPage extends StatefulWidget {
  const AnswerReviewPage({super.key});

  @override
  State<AnswerReviewPage> createState() => _AnswerReviewPageState();
}

class _AnswerReviewPageState extends State<AnswerReviewPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<LearningFlowCubit>().recordQuestionReviewViewed();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LearningFlowCubit, LearningFlowState>(
      builder: (context, state) {
        if (state.status != LearningFlowStatus.result ||
            state.questions.isEmpty) {
          return Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('Kembali ke beranda'),
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              onPressed: () => context.go('/result'),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            title: const Text('Review jawaban'),
          ),
          body: ListView.separated(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            itemCount: state.questions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 14),
            itemBuilder: (context, index) {
              final question = state.questions[index];
              final answer = state.answerFor(question.id);
              return _ReviewCard(
                index: index,
                question: question,
                answer: answer,
                showExplanation: context
                    .read<LearningFlowCubit>()
                    .canViewExplanation(question),
              );
            },
          ),
        );
      },
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.index,
    required this.question,
    required this.answer,
    required this.showExplanation,
  });

  final int index;
  final Question question;
  final AnswerRecord? answer;
  final bool showExplanation;

  @override
  Widget build(BuildContext context) {
    final selectedOption = _optionFor(answer?.selectedOptionId);
    final correctOption = _optionFor(question.correctOptionId)!;
    final isSkipped = answer == null || answer!.isSkipped;
    final isCorrect =
        !isSkipped && answer!.selectedOptionId == question.correctOptionId;
    final color = isCorrect
        ? const Color(0xFF147D78)
        : isSkipped
        ? const Color(0xFF9A6700)
        : Theme.of(context).colorScheme.error;
    final label = isCorrect
        ? 'Benar'
        : isSkipped
        ? 'Dilewati'
        : 'Belum tepat';

    return Card(
      key: Key('answer-review-$index'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Soal ${index + 1} • ${question.taxonomy.topicLabel}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(question.prompt, style: const TextStyle(height: 1.45)),
            const SizedBox(height: 14),
            _AnswerLine(
              label: 'Jawabanmu',
              value: selectedOption == null
                  ? 'Tidak dijawab'
                  : '${selectedOption.id.toUpperCase()}. ${selectedOption.text}',
              color: color,
            ),
            const SizedBox(height: 8),
            _AnswerLine(
              label: 'Jawaban benar',
              value: '${correctOption.id.toUpperCase()}. ${correctOption.text}',
              color: const Color(0xFF147D78),
            ),
            const Divider(height: 28),
            Text('Pembahasan', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 7),
            Text(
              showExplanation
                  ? question.explanation
                  : 'Pembahasan belum tersedia untuk paket akses ini.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  QuestionOption? _optionFor(String? id) {
    if (id == null) {
      return null;
    }
    for (final option in question.options) {
      if (option.id == id) {
        return option;
      }
    }
    return null;
  }
}

class _AnswerLine extends StatelessWidget {
  const _AnswerLine({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
