abstract final class AnalyticsEvents {
  static const practiceStarted = 'practice_started';
  static const questionAnswered = 'question_answered';
  static const practiceCompleted = 'practice_completed';
  static const drillStarted = 'drill_started';
  static const drillCompleted = 'drill_completed';
  static const resultViewed = 'result_viewed';
  static const weaknessViewed = 'weakness_viewed';
  static const recommendationViewed = 'recommendation_viewed';
  static const recommendationClicked = 'recommendation_clicked';
}

class AnalyticsEvent {
  const AnalyticsEvent({
    required this.name,
    required this.occurredAt,
    this.version = 1,
    this.properties = const {},
  });

  final String name;
  final DateTime occurredAt;
  final int version;
  final Map<String, Object> properties;
}

abstract interface class AnalyticsTracker {
  Future<void> track(String name, {Map<String, Object> properties = const {}});
}

class InMemoryAnalytics implements AnalyticsTracker {
  final List<AnalyticsEvent> _events = [];

  List<AnalyticsEvent> get events => List.unmodifiable(_events);

  @override
  Future<void> track(
    String name, {
    Map<String, Object> properties = const {},
  }) async {
    _events.add(
      AnalyticsEvent(
        name: name,
        occurredAt: DateTime.now().toUtc(),
        properties: properties,
      ),
    );
  }
}
