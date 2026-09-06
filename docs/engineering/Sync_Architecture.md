# ExamCoach — Sync Architecture

## Objective

Deliver locally committed learning and analytics operations to a remote service
without making scoring, progression, or session recovery depend on a network
connection.

## Current Scope

Step 8 implements the provider-neutral mobile sync engine:

- a real device connectivity adapter;
- deterministic ready-queue ordering and bounded batching;
- remote acknowledgement and idempotency outcomes;
- exponential retry and dead-letter handling;
- synced-record retention; and
- an initial/reconnect coordinator with single-flight worker execution.

The production `SyncRemoteGateway` and runtime bootstrap wiring are deliberately
deferred to Step 10, when authenticated Firebase data ownership and security
rules are available. Until then, the outbox remains authoritative and no local
operation is falsely marked as remotely synced.

## Delivery Flow

```text
Local learning/analytics transaction
  → Insert or replace stable outbox operation
  → Connectivity transport becomes available
  → Read ready operations by created_at, operation_id
  → Push bounded batch through SyncRemoteGateway
  → Apply one outcome per operation
      → accepted / duplicate / superseded: acknowledge locally
      → retryable failure / missing acknowledgement: schedule retry
      → permanent rejection / retry limit: dead-letter
  → Prune old acknowledged operations and their synced analytics sources
```

`connectivity_plus` only indicates that a network transport exists. It does not
prove internet or backend reachability. Every production gateway request must
therefore use timeouts and translate transient transport failures into
`SyncTransportException`; the worker keeps those operations pending.

## Worker Defaults

| Setting | Default | Purpose |
|---|---:|---|
| Batch size | 25 operations | Bound request and local transaction work |
| Maximum batches per run | 10 | Prevent an unbounded foreground run |
| First retry | 5 seconds | Recover quickly from a transient failure |
| Retry progression | Exponential, doubling | Reduce repeated load |
| Maximum retry delay | 15 minutes | Cap recovery latency |
| Maximum attempts | 5 | Quarantine permanently failing work |
| Synced retention | 7 days | Keep a short acknowledgement audit window |
| Prune limit | 200 records | Bound cleanup work |

Only `pending` operations with no `next_attempt_at`, or with a due
`next_attempt_at`, are ready. `deadLetter` operations are never retried or
pruned automatically.

## Acknowledgement and Conflict Policy

| Remote outcome | Local transition | Learning-state effect |
|---|---|---|
| `accepted` | `synced`, acknowledgement `accepted` | None |
| `duplicate` | `synced`, acknowledgement `duplicate` | None; idempotent replay succeeded |
| `superseded` | `synced`, acknowledgement `superseded` | None; never rewrite local score, answer, or insight |
| `retryableFailure` | Remain `pending`; set next attempt | None |
| Missing operation result | Remain `pending`; set next attempt | None |
| `rejected` | `deadLetter` immediately | None; preserve for diagnosis |
| Transport exception | Entire attempted batch remains pending or reaches retry cap | None |

The remote service owns comparison of its stored revision with the submitted
operation. `superseded` means the remote service already has a newer valid
version; it is a successful delivery outcome, not permission for the upload
worker to mutate deterministic local learning results.

## Idempotency and Ordering Contract

- `operation_id` is the idempotency key and must be unique remotely.
- The gateway must preserve the list order supplied by the worker.
- Pending work is read by `created_at ASC, operation_id ASC`.
- Session mutations carry `syncVersion`; the remote service accepts only valid
  forward state transitions and newer versions.
- Answer and session-progress operation IDs are stable and their pending local
  payload is replaced by the latest device write.
- Terminal cancellation, expiry, and completion operations remain explicit.
- Analytics event creation is idempotent by its stable event/operation ID.
- A retry after an uncertain response is safe: a remote duplicate
  acknowledgement closes the local operation.

Cross-device inbound reconciliation is not part of this upload worker. It will
be designed with Firebase authentication and remote ownership in Step 10.

## SQLite Schema V5

`sync_outbox` adds:

- `last_attempt_at` and `next_attempt_at` for scheduling;
- `synced_at` for acknowledgement retention;
- `dead_lettered_at` for permanent-failure audit;
- `acknowledgement` for `accepted`, `duplicate`, or `superseded`; and
- `remote_revision` for remote conflict evidence.

The readiness index covers `(status, next_attempt_at, created_at)`. Migration
from v4 preserves queued records and backfills legacy `synced` rows with their
creation time and an `accepted` acknowledgement.

## Retention

At the start of an online run, acknowledged outbox records older than seven days
are deleted in a bounded transaction. When an acknowledged record represents
an analytics event, its already-synced source row is deleted in the same
transaction. Learning sessions, answers, results, profiles, recommendations,
pending operations, and dead letters are not removed by this policy.

## Validation

Automated tests use real temporary SQLite databases and fake remote gateways to
cover:

- offline retention followed by reconnect delivery;
- concurrent trigger coalescing into one in-flight run;
- batching and accepted/duplicate/superseded acknowledgement;
- exponential backoff and the fifth-attempt dead-letter transition;
- uncertain transport delivery followed by an idempotent duplicate;
- permanent rejection and omitted acknowledgement handling;
- v1→v5 and direct v4→v5 migrations; and
- transactional retention of synced analytics while preserving dead letters.

Run:

```bash
flutter test test/services/sync test/persistence/local_persistence_integration_test.dart
flutter test
```

## Deferred to Remote Integration

- Authenticated Firebase `SyncRemoteGateway` implementation and bootstrap
  registration.
- Firestore security rules, server-side idempotency ledger, and revision
  validation.
- Cross-device download/reconciliation and account recovery.
- Operator visibility, reason classification, and controlled dead-letter
  re-drive.
- OS-scheduled background execution beyond app startup and reconnect triggers.
