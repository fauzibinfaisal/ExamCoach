import 'package:exam_coach/analytics/analytics_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts registered events with allow-listed scalar properties', () {
    final properties =
        AnalyticsEvents.validate(AnalyticsEvents.questionAnswered, {
          'sessionId': 'session_1',
          'questionId': 'question_1',
          'taxonomyNodeId': 'topic_1',
          'isCorrect': true,
          'timeSpentMs': 1200,
        });

    expect(properties['isCorrect'], isTrue);
  });

  test('rejects unknown events, properties, and oversized strings', () {
    expect(
      () => AnalyticsEvents.validate('unknown_event', const {}),
      throwsArgumentError,
    );
    expect(
      () => AnalyticsEvents.validate(AnalyticsEvents.resultViewed, const {
        'email': 'private@example.com',
      }),
      throwsArgumentError,
    );
    expect(
      () => AnalyticsEvents.validate(AnalyticsEvents.resultViewed, {
        'sessionId': 'x' * 241,
      }),
      throwsArgumentError,
    );
  });
}
