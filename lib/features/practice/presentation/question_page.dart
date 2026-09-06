import 'package:exam_coach/features/exam/domain/models/exam_session.dart';
import 'package:exam_coach/features/exam/domain/models/question.dart';
import 'package:exam_coach/features/learning/application/learning_flow_cubit.dart';
import 'package:exam_coach/features/learning/application/learning_flow_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class QuestionPage extends StatelessWidget {
  const QuestionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: BlocBuilder<LearningFlowCubit, LearningFlowState>(
        builder: (context, state) {
          final question = state.currentQuestion;
          if (state.status != LearningFlowStatus.answering ||
              question == null) {
            return _MissingSession(onReturn: () => context.go('/'));
          }

          final progress = (state.currentIndex + 1) / state.questions.length;
          final modeLabel = state.mode == ExamSessionMode.tryout
              ? 'TRYOUT DIAGNOSTIK'
              : 'DRILL ADAPTIF';

          return Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: Text(
                modeLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: Center(
                    child: Text(
                      '${state.currentIndex + 1}/${state.questions.length}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
            body: SafeArea(
              top: false,
              child: Column(
                children: [
                  LinearProgressIndicator(value: progress, minHeight: 5),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                      children: [
                        Row(
                          children: [
                            _Tag(label: question.taxonomy.topicLabel),
                            const SizedBox(width: 8),
                            _Tag(
                              label: _difficultyLabel(question.difficulty),
                              subdued: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Text(
                          question.prompt,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontSize: 22, height: 1.4),
                        ),
                        const SizedBox(height: 28),
                        for (final option in question.options) ...[
                          _AnswerOption(
                            option: option,
                            isSelected: state.selectedOptionId == option.id,
                            onTap: () => context
                                .read<LearningFlowCubit>()
                                .selectOption(option.id),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (state.errorMessage case final message?) ...[
                          const SizedBox(height: 8),
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
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Color(0xFFE1E8ED))),
                    ),
                    child: FilledButton(
                      key: const Key('submit-answer-button'),
                      onPressed:
                          state.selectedOptionId == null || state.isSaving
                          ? null
                          : () async {
                              final completed = await context
                                  .read<LearningFlowCubit>()
                                  .submitCurrentAnswer();
                              if (completed && context.mounted) {
                                context.go('/result');
                              }
                            },
                      child: Text(
                        state.isSaving
                            ? 'Menyimpan…'
                            : state.isLastQuestion
                            ? 'Lihat hasil'
                            : 'Lanjut',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static String _difficultyLabel(QuestionDifficulty difficulty) =>
      switch (difficulty) {
        QuestionDifficulty.easy => 'Mudah',
        QuestionDifficulty.medium => 'Sedang',
        QuestionDifficulty.hard => 'Sulit',
      };
}

class _AnswerOption extends StatelessWidget {
  const _AnswerOption({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final QuestionOption option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
        key: Key('answer-${option.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? colors.secondaryContainer : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? colors.secondary : const Color(0xFFD9E2E8),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? colors.secondary
                      : const Color(0xFFF0F4F6),
                ),
                child: Text(
                  option.id.toUpperCase(),
                  style: TextStyle(
                    color: isSelected ? Colors.white : colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  option.text,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, this.subdued = false});

  final String label;
  final bool subdued;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: subdued
            ? const Color(0xFFE9EEF2)
            : Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _MissingSession extends StatelessWidget {
  const _MissingSession({required this.onReturn});

  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline_rounded, size: 44),
              const SizedBox(height: 16),
              Text(
                'Sesi belum dimulai',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onReturn,
                child: const Text('Kembali ke beranda'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
