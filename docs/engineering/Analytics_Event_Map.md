# ExamCoach — Analytics Event Map

## Event Categories

### Acquisition
- app_installed
- onboarding_started
- onboarding_completed

### Learning
- practice_started
- question_answered
- question_skipped
- answer_changed
- practice_completed
- drill_started
- drill_completed

### Insight
- result_viewed
- weakness_viewed
- recommendation_viewed
- recommendation_clicked
- recommendation_completed

### AI
- ai_insight_requested
- ai_insight_generated
- ai_insight_viewed
- ai_quota_exhausted

### Monetization
- paywall_viewed
- purchase_started
- subscription_started
- subscription_renewed
- subscription_cancelled
- restore_purchase

### Habit
- daily_goal_viewed
- daily_goal_completed
- streak_started
- streak_continued
- streak_broken

## Event Envelope

```json
{
  "eventName": "question_answered",
  "eventVersion": 1,
  "userId": "user_id",
  "sessionId": "session_id",
  "timestamp": "ISO-8601",
  "appVersion": "1.0.0",
  "platform": "ios",
  "properties": {
    "questionId": "q_123",
    "taxonomyNodeId": "skill_456",
    "isCorrect": true,
    "timeSpentMs": 8200
  }
}
```

## Rules
- stable event names
- version schemas
- no secrets or unnecessary sensitive data
- centralized event creation
- offline queue
- batch upload

## Key Outcomes
Measure weakness before/after drills, accuracy/time improvement, readiness movement, recommendation effectiveness, retention, and conversion.
