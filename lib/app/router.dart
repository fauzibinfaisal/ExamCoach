import 'package:exam_coach/features/home/presentation/home_page.dart';
import 'package:exam_coach/features/practice/presentation/question_page.dart';
import 'package:exam_coach/features/practice/presentation/tryout_overview_page.dart';
import 'package:exam_coach/features/result/presentation/result_page.dart';
import 'package:go_router/go_router.dart';

GoRouter createAppRouter() {
  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePage()),
      GoRoute(
        path: '/overview',
        builder: (context, state) => const TryoutOverviewPage(),
      ),
      GoRoute(
        path: '/session',
        builder: (context, state) => const QuestionPage(),
      ),
      GoRoute(path: '/result', builder: (context, state) => const ResultPage()),
    ],
  );
}
