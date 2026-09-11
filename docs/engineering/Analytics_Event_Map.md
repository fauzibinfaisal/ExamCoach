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
- practice_cancelled
- practice_expired
- practice_completed
- drill_started
- drill_completed

### Insight
- result_viewed
- weakness_viewed
- recommendation_viewed
- recommendation_clicked
- recommendation_completed
- question_review_viewed

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
  "appVersion": "0.11.0",
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

Upload acknowledgement is transactional with the analytics source record.
Accepted, duplicate, and superseded operations mark the source synced; only old
synced analytics are pruned. Pending and dead-letter events remain available for
retry or diagnosis. See `Sync_Architecture.md`.

## Implemented Learning Events

| Event | Trigger | Key properties |
|---|---|---|
| `practice_started` | Local tryout session is durably created | `sessionId`, `mode` |
| `drill_started` | Recommended drill is durably created | `sessionId`, `mode` |
| `question_answered` | Question receives its first selected answer, including a previously skipped question | `sessionId`, `questionId`, `taxonomyNodeId`, `isCorrect`, `timeSpentMs` |
| `question_skipped` | Question is explicitly skipped | `sessionId`, `questionId`, `taxonomyNodeId`, `mode` |
| `answer_changed` | A saved selected option/skip state changes | `sessionId`, `questionId`, `fromOptionId`, `toOptionId`, `isCorrect` |
| `practice_cancelled` | User confirms cancellation of an active tryout or drill | `sessionId`, `mode`, `answeredCount`, `skippedCount` |
| `practice_expired` | Recovery finds an active session inactive for more than 24 hours | `sessionId`, `mode`, `inactiveForMs` |
| `practice_completed` | User explicitly finishes a reviewed tryout | `sessionId`, `score`, `skippedCount` |
| `drill_completed` | User explicitly finishes a reviewed drill | `sessionId`, `score`, `skippedCount` |
| `result_viewed` | Deterministic result becomes available | `sessionId` |
| `question_review_viewed` | Post-result answer review opens | `sessionId`, `mode`, `questionCount`, `skippedCount` |

## Implemented AI and Monetization Events

| Event | Trigger | Key properties |
|---|---|---|
| `ai_insight_requested` | Authenticated user starts a structured generation | `sessionId` |
| `ai_insight_generated` | Valid server response is accepted | `sessionId`, `provider`, `model`, `serverCache` |
| `ai_insight_viewed` | A generated or cached insight becomes visible | `sessionId`, `provider` |
| `ai_quota_exhausted` | Server rejects generation because daily quota is consumed | `sessionId` |
| `paywall_viewed` | Subscription page opens for the first time in its Cubit lifecycle | none |
| `purchase_started` | User selects a live RevenueCat offering package | `packageId` |
| `subscription_started` | Purchase completes and backend entitlement refresh returns | `packageId`, `planId` |
| `restore_purchase` | User explicitly asks RevenueCat to restore transactions | none |

Store product identifiers, prices, payment details, provider secrets, prompts,
and AI response text are not analytics properties. Subscription lifecycle
renewal/cancellation events remain deferred until a webhook and retention policy
are owner-approved.

Cancellation and expiry are terminal session outcomes, not completion events.
Their partial answers must not affect weakness, recommendation, or improvement
metrics.

## Key Outcomes
Measure weakness before/after drills, accuracy/time improvement, readiness movement, recommendation effectiveness, retention, and conversion.
