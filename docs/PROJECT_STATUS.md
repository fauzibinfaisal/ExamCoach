# ExamCoach Project Status

## Current Phase

Step 10 repository implementation is complete: Firebase authentication,
server-enforced remote ownership, idempotent outbox delivery, and safe
empty-device recovery are implemented and locally/emulator tested. The next
product milestone is Step 11 structured AI Coach, quota, entitlements, and
subscriptions.

A real Firebase development project has not been created, configured, or
deployed by this work. Until the owner supplies runtime values, the application
intentionally runs in local-only mode.

## Overall Progress

The deterministic offline loop remains the product source of truth:

```text
Home → Tryout overview → Answer or skip → Local commit → Pre-submit review
→ Edit or explicitly finish → Score → Answer/explanation review
→ Weakness analysis → Recommendation → Adaptive drill
→ Updated insight → Persisted history → Optional authenticated sync/recovery
```

SQLite stores content, sessions, answers, insight, analytics, delivery state,
and a permanent account binding. Firebase is an optional remote transport. All
remote writes pass through authenticated callable Functions; Firestore Rules
deny direct client writes. A clean second device may recover owned sessions and
answers, then recomputes correctness, score, weakness, and recommendation from
the installed deterministic local content.

Question generation remains provider-neutral and file-based. AI output enters
only as a draft; similarity checks and machine validation cannot replace named,
SHA-256-bound human review and explicit publication. No repository question pack
has been human-approved or published.

## 12-Step Delivery Roadmap

| Step | Milestone | Status |
|---:|---|---|
| 1 | Repository audit and persistent handoff baseline | Complete |
| 2 | Flutter shell and deterministic end-to-end learning loop | Complete |
| 3 | Offline SQLite persistence, recovery, analytics queue, and outbox | Complete |
| 4 | GitHub repository publication | Complete |
| 5 | Protected Git Flow with `develop` integration | Complete |
| 6 | Provider-neutral external-AI question-bank ingestion | Complete |
| 7 | Skip/edit/cancel/expiry and pre/post-result review | Complete |
| 8 | Connectivity-aware sync worker, retry, acknowledgement, and conflict policy | Complete |
| 9 | Human content review, similarity checks, and immutable publication | Complete |
| 10 | Firebase authentication, remote data, and cross-device recovery | Complete |
| 11 | Structured AI Coach, quota, entitlements, and subscriptions | Next |
| 12 | Product analytics, accessibility, performance, CI, and release readiness | Planned |

Current position: **Step 10 of 12 complete (83%)**. Current development version
is `0.10.0+10`; SQLite schema is v7. Step 10 was integrated into `develop`
through [PR #10](https://github.com/fauzibinfaisal/ExamCoach/pull/10);
`main` remains unchanged until owner testing and release approval.

## Step 10 Delivered

- Optional Firebase runtime configured only by explicit Dart defines, with a
  safe local-only fallback.
- Email/password registration, sign-in, password reset, sign-out, Account page,
  and Home sync status.
- Atomic first-account claim of legacy local sessions, analytics, and outbox
  owner fields; conflicting accounts are refused and sign-out preserves data.
- Authenticated callable upload and recovery gateways with timeout/error mapping.
- Node 22 Functions that enforce UID ownership, deterministic operation IDs,
  canonical payload hashes, immutable session meaning, complete-answer
  terminal state, and monotonically increasing per-user revisions.
- Firestore owner-read isolation, denied direct user-learning writes, and public
  access only to explicitly published content paths.
- Empty-device recovery bounded to 200 sessions, 500 answers per session, and
  5,000 answers total, with content, option, timestamp, lifecycle, and ownership
  validation plus local result recomputation.
- SQLite v7 `account_binding`, Firebase emulator setup, reproducible Functions
  lockfile, patched transitive dependency override, and development config
  template.
- Version `0.10.0+10`, Android debug artifact, and unsigned iOS smoke build.

Full implementation and validation evidence is in `IMPLEMENTATION_LOG.md`.
Activation and two-device testing are in
`engineering/Firebase_Integration.md`.

## Validation Snapshot

- Dart formatting: pass.
- Flutter analyzer: pass, no issues.
- Flutter test suite: pass, 53 tests.
- Backend core: pass, 10 tests.
- Auth/Firestore/Functions callable emulator: pass.
- Firestore Rules emulator: pass.
- Production npm audit: pass, zero vulnerabilities.
- Android debug build: pass; version `0.10.0`, build `10`, minSdk 24.
- Unsigned iOS smoke build: pass; version `0.10.0`, build `10`, iOS 15.
- iOS device/signing test: skipped by owner direction.
- Real Firebase deployment/two-device test: waiting for owner development
  project and runtime configuration.

## Next Steps

1. Owner: create a Firebase development project, enable Email/Password Auth,
   register the provisional app IDs, deploy Functions/Rules, and run the manual
   acceptance plan in `engineering/Firebase_Integration.md`.
2. Design Step 11 AI Coach request/response schemas with structured,
   evidence-linked output; deterministic results remain authoritative.
3. Add trusted server quota, entitlement, subscription validation, and AI
   provider-secret boundaries before enabling runtime AI.
4. Add user-visible AI failure/quota states and tests for cached/offline insight.
5. Have a real human review and publish production question content.
6. In Step 12, add CI-required checks, accessibility/performance validation,
   App Check/observability, release IDs/signing, and store readiness.

## Owner/External Blockers

- Production Firebase behavior cannot be accepted until the owner selects and
  configures a development project; no project ID or credential was invented.
- Production content cannot ship until a named human completes the review and
  publication workflow.
- Android/iOS release identifiers, signing, privacy/retention/deletion policy,
  and store configuration require owner decisions.
- Subscription products, tiers, prices, and entitlement policy require product
  decisions before Step 11 can be production-enabled.

## Known Limitations

- Recovery handles an empty local session store; it is not a general merge of
  two non-empty devices.
- A transient recovery-download failure is retried on the next app launch or
  authentication-state event; a dedicated manual re-pull action is not yet
  available.
- The database remains bound to its first account. Explicit export/reset and
  safe account switching are not implemented.
- Sync runs at startup and connectivity changes; OS-scheduled background work
  is not implemented.
- Dead letters are durable but have no operator inspection/re-drive UI.
- App Check, email-verification policy, provider sign-in, backup/restore,
  account deletion, remote retention, and production observability are pending.
- Firebase callable emulator ran on host Node 26 while deployed Functions are
  pinned to Node 22; exact-runtime CI remains Step 12 work.
- Flutter reports a future Kotlin built-in migration warning from current
  Firebase plugins; builds currently pass and package upgrades must be watched.
- Prototype and AI-generated questions remain development-only drafts.
- The 24-hour inactivity expiry and 0.82 similarity threshold remain provisional
  policies requiring production calibration.

## Governing Decisions

- Deterministic Dart scoring, weakness, recommendation, and drill selection are
  authoritative; remote services and AI cannot overwrite them.
- SQLite writes and outbox operations share transaction boundaries.
- Stable operation IDs, payload hashes, per-user revisions, and explicit remote
  outcomes make uncertain retries auditable and idempotent.
- One local database binds to one Firebase UID; sign-out does not delete or
  relabel data.
- Remote mutation uses authenticated callable Functions; direct client writes
  to user learning documents are denied.
- Existing local sessions win over inbound recovery. Clean-device recovery is
  validated against installed content and recomputed locally.
- `main` is release-only, `develop` is integration, and normal work uses
  `feature/*`/`bugfix/*` pull requests.
- Pre-1.0 builds use `0.MINOR.PATCH+BUILD`; database schema versions are
  independent.
