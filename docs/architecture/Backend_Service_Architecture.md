# ExamCoach — Backend Service Architecture

## High-Level Flow

```mermaid
flowchart TD
    A[Flutter App] --> B[Firebase Auth]
    A --> C[Firestore]
    A --> D[Cloud Functions]
    D --> E[AI Provider]
    D --> F[Analytics Pipeline]
    D --> G[Leaderboard Aggregation]
    D --> H[Subscription Validation]
    I[CMS] --> C
```

## Services
- auth
- content
- sync
- analytics
- learning intelligence
- AI
- quota
- leaderboard
- subscription
- notification

## Cloud Functions
Use for trusted operations:
- AI requests
- entitlement validation
- server quota
- leaderboard aggregation
- analytics processing
- scheduled jobs

## Security
Validate authenticated user, entitlement, quota, and request shape. Never expose AI provider secrets.

## Leaderboard
Prefer precomputed snapshots over expensive global realtime queries.

## Scalability
Start simple with Firebase. Introduce specialized services only when scale/query requirements justify them. Avoid premature microservices.
