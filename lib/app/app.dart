import 'package:exam_coach/app/router.dart';
import 'package:exam_coach/core/theme/app_theme.dart';
import 'package:exam_coach/features/learning/application/learning_flow_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class ExamCoachApp extends StatefulWidget {
  const ExamCoachApp({required this.learningFlowCubit, super.key});

  final LearningFlowCubit learningFlowCubit;

  @override
  State<ExamCoachApp> createState() => _ExamCoachAppState();
}

class _ExamCoachAppState extends State<ExamCoachApp> {
  late final GoRouter _router = createAppRouter();

  @override
  void dispose() {
    _router.dispose();
    widget.learningFlowCubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: widget.learningFlowCubit,
      child: MaterialApp.router(
        title: 'ExamCoach',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: _router,
      ),
    );
  }
}
