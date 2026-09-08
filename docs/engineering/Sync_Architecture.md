# ExamCoach — Sync Architecture

## Objective

Deliver locally committed learning and analytics operations to an authenticated
remote service without making scoring, progression, or local recovery depend on
a network connection.

## Implemented Scope

Step 8 established the provider-neutral mobile engine:

- real device-connectivity adapter;
- deterministic ready-queue ordering and bounded batching;
- explicit acknowledgement and idempotency outcomes;
- exponential retry, dead-letter handling, and synced retention; and
- startup/reconnect coordination with single-flight worker execution.

Step 10 supplies the optional Firebase boundary:

- Firebase email/password authentication and retained device/account binding;
- authenticated callable `FirebaseSyncGateway` with 30-second timeouts;
- `pushSyncBatch` and `pullRecoverySnapshot` Cloud Functions on Node 22;
- per-user Firestore revision and stable-operation ledger;
- owner-read/direct-client-write-denied Firestore Rules; and
- strictly validated empty-device recovery.

Firebase remains disabled unless all required runtime values are supplied. In
local-only mode the outbox remains authoritative, nothing is falsely marked
synced, and the complete learning loop keeps working. Real-project creation and
deployment remain owner-operated; see `Firebase_Integration.md`.

## Delivery Flow

```text
Local learning/analytics transaction
  → Insert or replace stable outbox operation
  → Connectivity transport becomes available
  → Read ready operations by created_at, operation_id
  → Require authenticated Firebase user
  → Push at most 25 operations through callable SyncRemoteGateway
  → Function verifies UID ownership, stable ID, payload, and state transition
  → Transactionally materialize entity + operation ledger + user revision
  → Apply one outcome per operation locally
      → accepted / duplicate / superseded: acknowledge
      → retryable failure / missing acknowledgement: schedule retry
      → permanent rejection / retry limit: dead-letter
      → authentication failure: preserve pending attempt unchanged
  → Prune old acknowledged operations and synced analytics sources
```

`connectivity_plus` only indicates that a network transport exists. It does not
prove backend reachability. The gateway translates callable failures into an
authentication or transport exception; local learning is never rolled back.

## Worker Defaults

| Setting | Default | Purpose |
|---|---:|---|
| Batch size | 25 operations | Bound request and transaction work |
| Maximum batches per run | 10 | Prevent an unbounded foreground run |
| First retry | 5 seconds | Recover quickly from transient failure |
| Retry progression | Exponential, doubling | Reduce repeated load |
| Maximum retry delay | 15 minutes | Cap recovery latency |
| Maximum attempts | 5 | Quarantine permanent failure |
| Synced retention | 7 days | Keep a short acknowledgement audit window |
| Prune limit | 200 records | Bound cleanup work |

Only `pending` operations whose `next_attempt_at` is absent or due are ready.
`deadLetter` operations are neither retried nor pruned automatically.

## Outcome and Conflict Policy

| Remote outcome | Local transition | Learning-state effect |
|---|---|---|
| `accepted` | `synced`, acknowledgement `accepted` | None |
| `duplicate` | `synced`, acknowledgement `duplicate` | None; replay succeeded |
| `superseded` | `synced`, acknowledgement `superseded` | None; never rewrite local evidence |
| `retryableFailure` | Stay pending; schedule next attempt | None |
| Missing result | Stay pending; schedule next attempt | None |
| `rejected` | `deadLetter` immediately | None; retain for diagnosis |
| Transport exception | Batch remains pending or reaches retry cap | None |
| Authentication missing/expired | Batch stays pending without attempt increment | Wait for sign-in |

`superseded` is a successful delivery outcome, not permission for the upload
worker to mutate local answers, score, weakness, recommendation, or insight.

## Idempotency and Server Validation

Pending work is ordered by `created_at ASC, operation_id ASC`. The stable IDs
are:

```text
<sessionId>:start
<sessionId>:answer:<questionId>
<sessionId>:progress
<sessionId>:cancelled
<sessionId>:expired
<sessionId>:complete
analytics:<eventId>
```

The server rejects arbitrary idempotency keys, forged owners, unsafe IDs,
oversized payloads, invalid UTC times, unsupported entity/operation types,
answer/session mismatches, and invalid lifecycle or revision transitions. The
authenticated UID—not payload identity—is authoritative.

The operation ledger stores the stable ID, canonical payload hash, client
creation time, processing time, and remote revision. The same payload returns
`duplicate`; an older mutation under a replaceable key returns `superseded`; a
newer valid answer/progress payload can advance that entity and ledger entry.

## Cross-Device Recovery

Inbound recovery is separate from upload acknowledgement:

```text
Authenticated UID
  → Pull owned sessions/answers and remote revision
  → Require matching permanent local account binding
  → If any local session exists: skip inbound import
  → Otherwise validate limits, lifecycle, timestamps, IDs, questions/options
  → Recompute correctness and completed score from installed local content
  → Import transactionally and rebuild deterministic insight in memory
```

At most 200 sessions, 500 answers per session, and 5,000 answers total are
accepted. Only one remote session may be active. Completed sessions require
every response. Unknown questions/options or a mismatched owner fail closed.
Step 10 deliberately does not merge two non-empty device histories; existing
local data is preserved and uploaded.

## Local Schema and Retention

SQLite schema v5 added retry scheduling, acknowledgement, remote revision,
dead-letter, and retention fields to `sync_outbox`. Schema v7 adds the singleton
`account_binding` table with Firebase UID, binding time, last recovery time, and
observed remote revision.

At online-run start, acknowledged outbox records older than seven days are
deleted in a bounded transaction. A linked already-synced analytics source is
deleted in the same transaction. Learning rows, pending work, and dead letters
are preserved.

## Validation

Automated coverage includes:

- offline retention, reconnect delivery, single-flight behavior, and batching;
- accepted/duplicate/superseded acknowledgement and uncertain retry;
- retry cap, rejection, omitted result, dead letter, and retention;
- authentication failure with unchanged pending attempt;
- account claim, owner-conflict refusal, and SQLite v1→v7 migration;
- empty-device import, local score recomputation, and local-data preservation;
- Firebase runtime configuration validation; and
- server core ownership, lifecycle, stable-ID, and canonical-hash validation.

Run:

```bash
flutter test test/services/sync test/features/auth \
  test/persistence/local_persistence_integration_test.dart
flutter test
npm --prefix functions test
```

The Firestore Rules test additionally requires installed npm dependencies and a
running Firestore emulator, as documented in `Firebase_Integration.md`.

## Deferred

- Owner configuration/deployment of real development and production Firebase
  projects.
- General reconciliation between two non-empty device histories.
- Explicit local-data export/reset and safe account switching.
- Operator dead-letter inspection/re-drive and OS-scheduled background sync.
- App Check, observability, backup, retention/deletion policy, and provider auth.
