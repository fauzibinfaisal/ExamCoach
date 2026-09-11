import 'package:exam_coach/features/auth/presentation/account_page.dart';
import 'package:exam_coach/features/ai_coach/presentation/ai_coach_page.dart';
import 'package:exam_coach/features/home/presentation/home_page.dart';
import 'package:exam_coach/features/practice/presentation/question_page.dart';
import 'package:exam_coach/features/practice/presentation/session_review_page.dart';
import 'package:exam_coach/features/practice/presentation/tryout_overview_page.dart';
import 'package:exam_coach/features/result/presentation/answer_review_page.dart';
import 'package:exam_coach/features/result/presentation/result_page.dart';
import 'package:exam_coach/features/subscription/presentation/subscription_page.dart';
import 'package:go_router/go_router.dart';

GoRouter createAppRouter() {
  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePage()),
      GoRoute(
        path: '/account',
        builder: (context, state) => const AccountPage(),
      ),
      GoRoute(
        path: '/ai-coach',
        builder: (context, state) => const AiCoachPage(),
      ),
      GoRoute(
        path: '/subscription',
        builder: (context, state) => const SubscriptionPage(),
      ),
      GoRoute(
        path: '/overview',
        builder: (context, state) => const TryoutOverviewPage(),
      ),
      GoRoute(
        path: '/session',
        builder: (context, state) => const QuestionPage(),
      ),
      GoRoute(path: '/result', builder: (context, state) => const ResultPage()),
      GoRoute(
        path: '/session-review',
        builder: (context, state) => const SessionReviewPage(),
      ),
      GoRoute(
        path: '/answer-review',
        builder: (context, state) => const AnswerReviewPage(),
      ),
    ],
  );
}
