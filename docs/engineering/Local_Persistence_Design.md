# ExamCoach — Local Persistence Design

## Objective

Keep the deterministic learning loop usable without a network connection and preserve user progress across application restarts.

## Technology

- SQLite through `sqflite` on Android and iOS.
- `sqflite_common_ffi` only in tests so database behavior can be exercised with real SQLite files on the development host.
- Explicit SQL schema and migrations; no generated persistence code.

The database is opened through `ExamCoachDatabase`, which accepts a `DatabaseFactory`. Production uses the native mobile factory; tests inject the FFI factory.

## Schema Version

Current schema: `8`.

- Version 1: question packs, questions, exam sessions, user answers, weakness profiles, and recommendations.
- Version 2: durable analytics events and the idempotent sync outbox.
- Version 3: question-pack title, immutable tryout selection, AI generator metadata, author, and reviewer audit fields.
- Version 4: explicit skipped-answer state for resumable response editing and review.
- Version 5: sync scheduling, acknowledgement, remote-revision, dead-letter,
  and retention metadata.
- Version 6: immutable content digest, human review evidence, provenance
  decision, and publication audit metadata.
- Version 7: single-owner Firebase account binding, last-recovery time, and
  observed remote revision.
- Version 8: authenticated structured AI Coach response cache keyed by canonical
  learning context, with provider/prompt metadata and explicit expiry.

Unknown migrations and database downgrades fail explicitly instead of silently rebuilding or deleting user data.

## Persisted Data

### Content

- `question_packs`
- `questions`

The local prototype pack is seeded once and remains `draft`. Versioned
external-AI packs can be loaded from the bundled question-bank manifest and are
inserted transactionally if their immutable pack ID has not been seen before.
New AI output enters as `draft`; only digest-bound human review can create a
`validated` artifact, and only a separate publisher action can create a
`published` artifact.

When SQLite already contains a pack ID, bootstrap computes the immutable content
fingerprint from stored data and compares it with the bundled artifact. A
matching pack may advance from draft to validated/published, with review and
publication metadata updated transactionally on the pack and its questions. A
content mismatch or lifecycle regression fails closed. Stored review fields are
`reviewed_at`, `review_notes`, `provenance_decision`, `provenance_notes`,
`content_sha256`, `review_checklist_json`, `publisher`, and `published_at`.

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

The outbox primary key makes retries idempotent. Answer and progress payloads replace their pending operation with the newest local version when edited. Failed attempts retain the operation, increment `attempts`, record bounded `last_error` and `last_attempt_at`, and schedule `next_attempt_at`. A successful analytics upload transactionally marks both the outbox operation and source analytics event as synced.

Delivery metadata records `synced_at`, `dead_lettered_at`, the remote
acknowledgement (`accepted`, `duplicate`, or `superseded`), and an optional
remote revision. Ready operations are ordered by `created_at` and
`operation_id`. The worker uses five attempts, exponential delay from five
seconds up to fifteen minutes, batches of 25, and at most ten batches per run.
See `Sync_Architecture.md` for the full state machine and conflict contract.

### Account Binding

- `account_binding`

The table has exactly zero or one row (`singleton = 1`) containing the bound
Firebase UID, binding time, last successful empty-device recovery time, and
observed remote revision. First sign-in atomically claims every `local_user`
session and analytics row and rewrites matching queued payload ownership. A
conflicting existing owner aborts the transaction. Sign-out does not delete the
binding or local data, and a different account is refused until a future
explicit destructive reset workflow exists.

### AI Coach Cache

- `ai_coach_insights`

Only server-validated responses for an authenticated owner are persisted.
Rows are keyed by the canonical context SHA-256, retain the source completed
session as a foreign key, and store provider/model/prompt version plus generated
and expiry timestamps. Expired entries are deleted on read. Cache failure never
hides a valid server response or blocks deterministic insight.

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
  → Initialize optional Firebase runtime
      → Disabled/invalid: remain fully local
      → Authenticated first sign-in: atomically bind local owner
      → No local sessions: validate and import owned remote snapshot
      → Existing local sessions: skip inbound import and upload outbox
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
- First account claim + session/analytics/outbox owner rewrite + binding insert.
- Empty-device remote session/answer import + recovery metadata update.
- AI Coach response upsert after a server-validated generation/cache response.
- Mark analytics synced + update source event status.
- Prune an old synced analytics outbox operation + its synced source event.

## Tests

The integration suite uses temporary SQLite files and verifies:

- schema creation and question-pack persistence;
- migration from schema v1 through v2, v3, v4, v5, v6, v7, and v8;
- direct v4→v5 migration with acknowledgement backfill;
- generated-pack metadata import, activation, and idempotent reload;
- immutable draft→validated→published lifecycle persistence and tamper refusal;
- answer-by-answer persistence;
- database close and reopen during an active tryout;
- restoration at the exact next question;
- restoration directly into pre-submit review after all responses are saved;
- nullable skipped-answer round-trip and answer-change behavior;
- durable cancellation and 24-hour expiry with completed-history isolation;
- completed score, history, weakness, and recommendation restoration;
- idempotent outbox insertion;
- failed-attempt scheduling, acknowledgement metadata, and dead-letter state;
- durable analytics queue behavior;
- offline→reconnect delivery, batched outcomes, retry limits, uncertain
  delivery, and synced-retention cleanup.
- atomic local account claim, conflicting-account refusal, empty-device remote
  import, local score recomputation, and local-data preservation.
- AI Coach cache round-trip, owner scoping, expiry deletion, and completed
  session linkage.

## Deferred

- General multi-writer reconciliation beyond empty-device recovery.
- Explicit local-data export/reset and safe account switching.
- Operator inspection and controlled re-drive for dead-letter operations.
- OS-scheduled background execution beyond startup/reconnect triggers.
- Encryption policy for future account or sensitive data.
- Download/update/retire lifecycle for production question packs.
- Remote CMS distribution, revocation, and retirement of published packs.
