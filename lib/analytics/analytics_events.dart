abstract final class AnalyticsEvents {
  static const practiceStarted = 'practice_started';
  static const questionAnswered = 'question_answered';
  static const questionSkipped = 'question_skipped';
  static const answerChanged = 'answer_changed';
  static const practiceCancelled = 'practice_cancelled';
  static const practiceExpired = 'practice_expired';
  static const questionReviewViewed = 'question_review_viewed';
  static const practiceCompleted = 'practice_completed';
  static const drillStarted = 'drill_started';
  static const drillCompleted = 'drill_completed';
  static const resultViewed = 'result_viewed';
  static const weaknessViewed = 'weakness_viewed';
  static const recommendationViewed = 'recommendation_viewed';
  static const recommendationClicked = 'recommendation_clicked';
  static const aiInsightRequested = 'ai_insight_requested';
  static const aiInsightGenerated = 'ai_insight_generated';
  static const aiInsightViewed = 'ai_insight_viewed';
  static const aiQuotaExhausted = 'ai_quota_exhausted';
  static const paywallViewed = 'paywall_viewed';
  static const purchaseStarted = 'purchase_started';
  static const subscriptionStarted = 'subscription_started';
  static const restorePurchase = 'restore_purchase';

  static const Map<String, Set<String>> allowedProperties = {
    practiceStarted: {'sessionId', 'mode'},
    questionAnswered: {
      'sessionId',
      'questionId',
      'taxonomyNodeId',
      'isCorrect',
      'timeSpentMs',
    },
    questionSkipped: {'sessionId', 'questionId', 'taxonomyNodeId', 'mode'},
    answerChanged: {
      'sessionId',
      'questionId',
      'fromOptionId',
      'toOptionId',
      'isCorrect',
    },
    practiceCancelled: {'sessionId', 'mode', 'answeredCount', 'skippedCount'},
    practiceExpired: {'sessionId', 'mode', 'inactiveForMs'},
    questionReviewViewed: {
      'sessionId',
      'mode',
      'questionCount',
      'skippedCount',
    },
    practiceCompleted: {'sessionId', 'score', 'skippedCount'},
    drillStarted: {'sessionId', 'mode'},
    drillCompleted: {'sessionId', 'score', 'skippedCount'},
    resultViewed: {'sessionId'},
    weaknessViewed: {'sessionId'},
    recommendationViewed: {'sessionId', 'target'},
    recommendationClicked: {'target'},
    aiInsightRequested: {'sessionId'},
    aiInsightGenerated: {'sessionId', 'provider', 'model', 'serverCache'},
    aiInsightViewed: {'sessionId', 'provider'},
    aiQuotaExhausted: {'sessionId'},
    paywallViewed: <String>{},
    purchaseStarted: {'packageId'},
    subscriptionStarted: {'packageId', 'planId'},
    restorePurchase: <String>{},
  };

  static Map<String, Object> validate(
    String name,
    Map<String, Object> properties,
  ) {
    final allowed = allowedProperties[name];
    if (allowed == null) {
      throw ArgumentError.value(name, 'name', 'Unregistered analytics event');
    }
    final unexpected = properties.keys.where((key) => !allowed.contains(key));
    if (unexpected.isNotEmpty) {
      throw ArgumentError(
        'Unexpected properties for $name: ${unexpected.join(', ')}',
      );
    }
    for (final entry in properties.entries) {
      final value = entry.value;
      final isSupported =
          value is bool ||
          value is int ||
          (value is double && value.isFinite) ||
          (value is String && value.length <= 240);
      if (!isSupported) {
        throw ArgumentError('Unsafe analytics value for ${entry.key}');
      }
    }
    return Map.unmodifiable(properties);
  }
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
    final validated = AnalyticsEvents.validate(name, properties);
    _events.add(
      AnalyticsEvent(
        name: name,
        occurredAt: DateTime.now().toUtc(),
        properties: validated,
      ),
    );
  }
}
