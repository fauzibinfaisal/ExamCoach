import 'package:exam_coach/features/learning/application/learning_flow_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

Future<void> confirmAndCancelSession(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Batalkan sesi?'),
      content: const Text(
        'Jawaban pada sesi ini tidak akan dihitung ke hasil belajarmu. Riwayat sesi sebelumnya tetap aman.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Lanjut mengerjakan'),
        ),
        FilledButton(
          key: const Key('confirm-cancel-session-button'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Batalkan sesi'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  final cancelled = await context.read<LearningFlowCubit>().cancelSession();
  if (cancelled && context.mounted) {
    context.go('/');
  }
}
