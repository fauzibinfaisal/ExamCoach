import 'package:exam_coach/features/exam/domain/models/question.dart';
import 'package:exam_coach/features/learning/application/learning_flow_cubit.dart';
import 'package:exam_coach/features/learning/application/learning_flow_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class TryoutOverviewPage extends StatelessWidget {
  const TryoutOverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LearningFlowCubit, LearningFlowState>(
      builder: (context, state) {
        if (state.status != LearningFlowStatus.answering ||
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
              onPressed: () => context.go('/'),
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Batalkan tryout',
            ),
            title: const Text('Ringkasan tryout'),
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                    children: [
                      Text(
                        '6 soal untuk membaca pola awalmu',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Jawab berurutan tanpa umpan balik langsung. Hasil dihitung setelah semua soal selesai.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 24),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            children: [
                              for (
                                var index = 0;
                                index < state.questions.length;
                                index++
                              )
                                _QuestionListItem(
                                  index: index,
                                  question: state.questions[index],
                                  showDivider:
                                      index < state.questions.length - 1,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                  color: Colors.white,
                  child: FilledButton.icon(
                    key: const Key('begin-session-button'),
                    onPressed: () => context.go('/session'),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Mulai menjawab'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QuestionListItem extends StatelessWidget {
  const _QuestionListItem({
    required this.index,
    required this.question,
    required this.showDivider,
  });

  final int index;
  final Question question;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final difficulty = switch (question.difficulty) {
      QuestionDifficulty.easy => 'Mudah',
      QuestionDifficulty.medium => 'Sedang',
      QuestionDifficulty.hard => 'Sulit',
    };
    return Column(
      children: [
        ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            child: Text(
              '${index + 1}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          title: Text(
            question.taxonomy.topicLabel,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text('$difficulty • target 60 detik'),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
        if (showDivider) const Divider(height: 1, indent: 72, endIndent: 16),
      ],
    );
  }
}
