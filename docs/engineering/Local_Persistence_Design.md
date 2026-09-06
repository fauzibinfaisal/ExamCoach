# ExamCoach — Local Persistence Design

## Objective

Keep the deterministic learning loop usable without a network connection and preserve user progress across application restarts.

## Technology

- SQLite through `sqflite` on Android and iOS.
- `sqflite_common_ffi` only in tests so database behavior can be exercised with real SQLite files on the development host.
- Explicit SQL schema and migrations; no generated persistence code.

The database is opened through `ExamCoachDatabase`, which accepts a `DatabaseFactory`. Production uses the native mobile factory; tests inject the FFI factory.

## Schema Version

Current schema: `2`.

- Version 1: question packs, questions, exam sessions, user answers, weakness profiles, and recommendations.
- Version 2: durable analytics events and the idempotent sync outbox.

Unknown migrations and database downgrades fail explicitly instead of silently rebuilding or deleting user data.

## Persisted Data

### Content

- `question_packs`
- `questions`

The local prototype pack is seeded once and remains `draft`. This is a development exception; production offline packs must be published and human-validated.

### Learning

- `exam_sessions`
- `user_answers`
- `weakness_profiles`
- `recommendations`

Only one active session is expected. Starting another session marks an older active session as cancelled. Each accepted answer and the session cursor are committed in one transaction before the UI advances.

### Delivery

- `analytics_events`
- `sync_outbox`

Analytics creation writes the event and its outbox operation in one transaction. Learning mutations use deterministic operation IDs:

```text
<sessionId>:start
<sessionId>:answer:<questionId>
<sessionId>:complete
analytics:<eventId>
```

The outbox primary key makes retries idempotent. Failed attempts retain the operation, increment `attempts`, and record `last_error`. A successful analytics upload marks both the outbox operation and source analytics event as synced.

## Recovery Flow

```text
Application bootstrap
  → Open/migrate SQLite
  → Seed/load local question pack
  → Load latest profiles, recommendation, score, and completed answers
  → Find active session
      → Resolve its stable question IDs
      → Restore submitted answers and current index
      → Show “Lanjutkan sesi” on Home
```

If an active session references unavailable questions, the application does not guess or remap content. It returns to Home with a recovery error.

If database bootstrap itself fails, the application reports a Flutter error and falls back to the transient repository so the deterministic learning loop can still launch. Data created in that fallback mode is not durable.

## Transaction Boundaries

- Start session + start outbox operation.
- Answer upsert + session cursor/version update + answer outbox operation.
- Session completion + profile upserts + recommendation insert + completion outbox operation.
- Analytics event + analytics outbox operation.
- Mark analytics synced + update source event status.

## Tests

The integration suite uses temporary SQLite files and verifies:

- schema creation and question-pack persistence;
- migration from schema v1 to v2;
- answer-by-answer persistence;
- database close and reopen during an active tryout;
- restoration at the exact next question;
- completed score, history, weakness, and recommendation restoration;
- idempotent outbox insertion;
- failed-attempt metadata and successful sync state;
- durable analytics queue behavior.

## Deferred

- Connectivity observer and background sync worker.
- Retry backoff and dead-letter policy.
- Remote acknowledgement protocol and conflict resolver.
- Retention/pruning for completed sessions, synced analytics, and outbox records.
- Encryption policy for future account or sensitive data.
- Download/update/retire lifecycle for production question packs.
