import 'package:exam_coach/features/learning/application/learning_flow_cubit.dart';
import 'package:exam_coach/features/learning/application/learning_flow_state.dart';
import 'package:exam_coach/features/practice/presentation/session_cancel_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class SessionReviewPage extends StatelessWidget {
  const SessionReviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LearningFlowCubit, LearningFlowState>(
      builder: (context, state) {
        if (state.status != LearningFlowStatus.reviewing ||
            !state.allQuestionsResponded) {
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
              tooltip: 'Kembali ke soal terakhir',
              onPressed: state.isSaving
                  ? null
                  : () async {
                      final moved = await context
                          .read<LearningFlowCubit>()
                          .goToQuestion(state.questions.length - 1);
                      if (moved && context.mounted) {
                        context.go('/session');
                      }
                    },
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            title: const Text('Periksa jawaban'),
            actions: [
              IconButton(
                tooltip: 'Batalkan sesi',
                onPressed: state.isSaving
                    ? null
                    : () => confirmAndCancelSession(context),
                icon: const Icon(Icons.close_rounded),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    children: [
                      Text(
                        'Semua soal sudah direspons',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${state.answeredCount} dijawab • ${state.skippedCount} dilewati. Kamu masih bisa mengubah jawaban sebelum hasil dihitung.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 22),
                      Card(
                        child: Column(
                          children: [
                            for (
                              var index = 0;
                              index < state.questions.length;
                              index++
                            )
                              _ResponseTile(
                                index: index,
                                topic:
                                    state.questions[index].taxonomy.topicLabel,
                                isSkipped:
                                    state
                                        .answerFor(state.questions[index].id)
                                        ?.isSkipped ??
                                    true,
                                showDivider: index < state.questions.length - 1,
                                onTap: state.isSaving
                                    ? null
                                    : () async {
                                        final moved = await context
                                            .read<LearningFlowCubit>()
                                            .goToQuestion(index);
                                        if (moved && context.mounted) {
                                          context.go('/session');
                                        }
                                      },
                              ),
                          ],
                        ),
                      ),
                      if (state.errorMessage case final message?) ...[
                        const SizedBox(height: 16),
                        Text(
                          message,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE1E8ED))),
                  ),
                  child: FilledButton.icon(
                    key: const Key('finish-session-button'),
                    onPressed: state.isSaving
                        ? null
                        : () async {
                            final completed = await context
                                .read<LearningFlowCubit>()
                                .completeCurrentSession();
                            if (completed && context.mounted) {
                              context.go('/result');
                            }
                          },
                    icon: const Icon(Icons.flag_rounded),
                    label: Text(
                      state.isSaving
                          ? 'Menghitung hasil…'
                          : 'Selesaikan & lihat hasil',
                    ),
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

class _ResponseTile extends StatelessWidget {
  const _ResponseTile({
    required this.index,
    required this.topic,
    required this.isSkipped,
    required this.showDivider,
    required this.onTap,
  });

  final int index;
  final String topic;
  final bool isSkipped;
  final bool showDivider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        ListTile(
          key: Key('edit-question-$index'),
          onTap: onTap,
          leading: CircleAvatar(
            backgroundColor: isSkipped
                ? const Color(0xFFFFE8C2)
                : colors.secondaryContainer,
            child: Icon(
              isSkipped ? Icons.fast_forward_rounded : Icons.check_rounded,
              color: isSkipped ? const Color(0xFF8A5A00) : colors.secondary,
            ),
          ),
          title: Text(
            'Soal ${index + 1} • $topic',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(isSkipped ? 'Dilewati' : 'Sudah dijawab'),
          trailing: const Icon(Icons.edit_rounded),
        ),
        if (showDivider) const Divider(height: 1, indent: 72),
      ],
    );
  }
}
