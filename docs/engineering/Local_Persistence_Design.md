# ExamCoach — Local Persistence Design

## Objective

Keep the deterministic learning loop usable without a network connection and preserve user progress across application restarts.

## Technology

- SQLite through `sqflite` on Android and iOS.
- `sqflite_common_ffi` only in tests so database behavior can be exercised with real SQLite files on the development host.
- Explicit SQL schema and migrations; no generated persistence code.

The database is opened through `ExamCoachDatabase`, which accepts a `DatabaseFactory`. Production uses the native mobile factory; tests inject the FFI factory.

## Schema Version

Current schema: `4`.

- Version 1: question packs, questions, exam sessions, user answers, weakness profiles, and recommendations.
- Version 2: durable analytics events and the idempotent sync outbox.
- Version 3: question-pack title, immutable tryout selection, AI generator metadata, author, and reviewer audit fields.
- Version 4: explicit skipped-answer state for resumable response editing and review.

Unknown migrations and database downgrades fail explicitly instead of silently rebuilding or deleting user data.

## Persisted Data

### Content

- `question_packs`
- `questions`

The local prototype pack is seeded once and remains `draft`. Versioned external-AI packs can be loaded from the bundled question-bank manifest and are inserted transactionally if their immutable pack ID has not been seen before. Generated packs also remain `draft`; this is a development exception, and production offline packs must be published and human-validated.

### Learning

- `exam_sessions`
- `user_answers`
- `weakness_profiles`
- `recommendations`

Only one active session is expected. Starting another session marks an older active session as cancelled. Each answer or explicit skip and the session cursor are committed in one transaction before the UI advances. Response edits replace the same answer row, retain a sticky changed-answer flag, and accumulate time spent.

Cancelled and expired sessions remain stored for audit and future sync, but only completed-session answers contribute to history, scores, weakness profiles, and recommendations. Active sessions expire during recovery after more than 24 hours of inactivity.

### Delivery

- `analytics_events`
- `sync_outbox`

Analytics creation writes the event and its outbox operation in one transaction. Learning mutations use deterministic operation IDs:

```text
<sessionId>:start
<sessionId>:answer:<questionId>
<sessionId>:progress
<sessionId>:cancelled
<sessionId>:expired
<sessionId>:complete
analytics:<eventId>
```

The outbox primary key makes retries idempotent. Answer and progress payloads replace their pending operation with the newest local version when edited. Failed attempts retain the operation, increment `attempts`, and record `last_error`. A successful analytics upload marks both the outbox operation and source analytics event as synced.

## Recovery Flow

```text
Application bootstrap
  → Open/migrate SQLite
  → Validate bundled question-bank manifest and generated packs
  → Seed the prototype and transactionally import unseen asset packs
  → Select the manifest's active six-question tryout
  → Load latest profiles, recommendation, score, and completed answers
  → Find active session
      → Resolve its stable question IDs
      → Restore submitted answers and current index
      → If all responses exist, restore pre-submit review
      → Otherwise restore the exact saved question
      → If inactive for more than 24 hours, persist expiry and return Home
      → Show “Lanjutkan sesi” on Home for a recoverable active session
```

If an active session references unavailable questions, the application does not guess or remap content. It returns to Home with a recovery error.

If database bootstrap itself fails, the application reports a Flutter error and falls back to the transient repository so the deterministic learning loop can still launch. Data created in that fallback mode is not durable.

## Transaction Boundaries

- Start session + start outbox operation.
- Answer upsert + session cursor/version update + answer outbox operation.
- Review/edit cursor update + replaceable progress outbox operation.
- Cancellation or expiry + terminal-status outbox operation.
- Session completion + profile upserts + recommendation insert + completion outbox operation.
- Analytics event + analytics outbox operation.
- Mark analytics synced + update source event status.

## Tests

The integration suite uses temporary SQLite files and verifies:

- schema creation and question-pack persistence;
- migration from schema v1 through v2, v3, and v4;
- generated-pack metadata import, activation, and idempotent reload;
- answer-by-answer persistence;
- database close and reopen during an active tryout;
- restoration at the exact next question;
- restoration directly into pre-submit review after all responses are saved;
- nullable skipped-answer round-trip and answer-change behavior;
- durable cancellation and 24-hour expiry with completed-history isolation;
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
