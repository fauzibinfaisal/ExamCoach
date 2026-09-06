# ExamCoach — Database ERD

## Logical ERD

```mermaid
erDiagram
    USER ||--o{ EXAM_SESSION : starts
    EXAM ||--o{ TEST : contains
    TEST ||--o{ QUESTION : contains
    QUESTION }o--|| TAXONOMY_NODE : mapped_to
    EXAM_SESSION ||--o{ USER_ANSWER : contains
    QUESTION ||--o{ USER_ANSWER : answered_in
    USER ||--o{ WEAKNESS_PROFILE : owns
    TAXONOMY_NODE ||--o{ WEAKNESS_PROFILE : measures
    USER ||--o{ RECOMMENDATION : receives
    USER ||--o{ AI_USAGE : consumes
    USER ||--o{ SUBSCRIPTION : owns
    USER ||--o{ ANALYTICS_EVENT : generates
    EXAM_SESSION ||--o{ SYNC_OUTBOX_OPERATION : produces
    ANALYTICS_EVENT ||--o| SYNC_OUTBOX_OPERATION : queued_as
```

## Core Entities
- User
- Exam
- Test
- TaxonomyNode
- Question
- ExamSession
- UserAnswer
- WeaknessProfile
- Recommendation
- AIUsage
- Subscription
- AnalyticsEvent
- SyncOutboxOperation

## Important Fields
ExamSession: userId, testId, mode, start/end time, score, status, syncVersion.
UserAnswer: sessionId, questionId, selectedAnswer, isSkipped, correctness, timeSpentMs, changedAnswer.
WeaknessProfile: userId, taxonomyNodeId, score, confidence, sampleSize, trend.
Recommendation: userId, targetNodeId, reasonCode, priority, actionType, generatedAt, expiry.
QuestionPack: validationStatus, reviewer, reviewedAt, reviewNotes,
provenanceDecision, provenanceNotes, contentSha256, reviewChecklist,
publisher, publishedAt.
SyncOutboxOperation: operationId, entityType, entityId, operation, payloadJson,
createdAt, attempts, status, lastAttemptAt, nextAttemptAt, syncedAt,
deadLetteredAt, acknowledgement, remoteRevision.

## Storage
Firestore is appropriate for the initial mobile/backend workload. Add analytical warehouse/SQL infrastructure later when query volume or B2B analytics justify it.

## Local Store
Cache only data required for offline learning: published question packs, taxonomy snapshot, active session, answers, sync queue, recommendations, and AI cache.

The implemented SQLite schema, transaction boundaries, recovery behavior, and
migration policy are documented in `Local_Persistence_Design.md`. Session
response, cancellation, expiry, and review behavior are documented in
`Session_Controls_and_Review.md`. Delivery ordering, retry, acknowledgement,
conflict, and retention rules are documented in `Sync_Architecture.md`. Human
content review and publication are documented in
`../operations/Human_Question_Review_Workflow.md`.
