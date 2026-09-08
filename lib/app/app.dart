import 'package:exam_coach/app/router.dart';
import 'package:exam_coach/core/theme/app_theme.dart';
import 'package:exam_coach/features/auth/application/auth_cubit.dart';
import 'package:exam_coach/features/learning/application/learning_flow_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class ExamCoachApp extends StatefulWidget {
  const ExamCoachApp({
    required this.learningFlowCubit,
    required this.authCubit,
    super.key,
  });

  final LearningFlowCubit learningFlowCubit;
  final AuthCubit authCubit;

  @override
  State<ExamCoachApp> createState() => _ExamCoachAppState();
}

class _ExamCoachAppState extends State<ExamCoachApp> {
  late final GoRouter _router = createAppRouter();

  @override
  void dispose() {
    _router.dispose();
    widget.authCubit.close();
    widget.learningFlowCubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: widget.learningFlowCubit),
        BlocProvider.value(value: widget.authCubit),
      ],
      child: MaterialApp.router(
        title: 'ExamCoach',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: _router,
      ),
    );
  }
}
