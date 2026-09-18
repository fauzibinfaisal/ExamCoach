# ExamCoach Project Status

## Current Phase

Step 12 repository implementation is complete. All 12 development-roadmap
milestones now have code, automated validation, and documented handoff. Step 12
adds CI, analytics privacy contracts, large-text accessibility protection,
artifact budgets, structured observability, staged App Check, and opt-in
Crashlytics without weakening the deterministic offline-first learning loop.

Real Firebase/OpenAI/RevenueCat/store environments have not been created,
configured, or deployed by this work. Until the owner supplies the documented
values and decisions, Firebase remains optional, AI/subscriptions fail closed,
and local learning continues normally.

## Overall Progress

```text
Home → Tryout → Review → Deterministic score/weakness/recommendation
→ Adaptive drill → Updated insight → Persisted history
→ Optional authenticated sync/recovery
→ Optional structured AI explanation
→ Optional store purchase → backend-verified entitlement → plan quota
```

SQLite stores content, sessions, answers, insight, analytics, delivery state,
permanent account binding, and expiring AI cache. Firebase clients can read only
their own user tree and cannot write it directly. Functions own remote learning
mutation, quota, AI requests, and entitlement materialization.

Question generation remains provider-neutral and file-based. AI-generated
questions are drafts until named, digest-bound human review and explicit
publication. AI Coach is separate: it explains deterministic learning facts and
cannot score, decide correctness/weakness/recommendation, select questions, or
guarantee passing.

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
| 11 | Structured AI Coach, quota, entitlements, and subscriptions | Complete |
| 12 | Product analytics, accessibility, performance, CI, and release readiness | Complete |

Current position: **Step 12 of 12 complete (100% repository roadmap)**. Current
development version is `0.12.0+12`; SQLite schema remains v8. Step 12 was
squash-merged into `develop` through
[PR #13](https://github.com/fauzibinfaisal/ExamCoach/pull/13) after all hosted CI
gates passed. `main` remains release-only and unchanged.

## New Web CBT Track

The owner has accepted the initial product contract for a desktop-first linked
mock test. An authenticated mobile user creates a browser link scoped to one
tryout; it is valid for at most 12 hours from server-side creation and becomes
permanently unusable after completion, expiry, or owner revocation. The first
browser claim is session-bound so a copied link cannot silently take over the
attempt.

This track is at **W0 of W5 (product definition in progress)**. No web runtime,
link backend, hosting, or production environment has been implemented. The
mobile roadmap remains complete and its current version does not change for a
documentation-only product definition.

The source of truth is `product/Web_Linked_Mock_Test_PRD.md`. The next session
must decide the web stack/repository boundary and trusted sharing of learning
contracts before implementation.

## Step 12 Delivered

- GitHub Actions gates pull requests with formatting, pre-1.0 metadata,
  analyzer, all Flutter tests, Functions tests/audit, Firestore Rules and
  callable emulators, Android build, APK budget, and artifact upload.
- Flutter and Functions independently allow-list analytics event names,
  properties, scalar values, and string size before data can enter the outbox
  or Firestore.
- Structured sync/recovery/AI/subscription logs use a truncated SHA-256 subject
  hash and bounded dimensions without raw UID, learning content, AI text,
  payment data, price, or secret values.
- Opt-in Firebase App Check uses Play Integrity on Android and App Attest with
  DeviceCheck fallback on Apple; the debug provider and callable enforcement
  are separate, default-off rollout controls.
- Opt-in Crashlytics collection installs Flutter-framework and unhandled async
  error reporting only when explicitly enabled.
- Screen-reader labels for question choices, progress, and score plus automated
  320-pixel/200%-text coverage. Responsive session controls/tags fix the
  overflows found by that regression test.
- Automated pre-1.0 version and 190 MiB debug-APK guards, plus honest physical
  Android startup/frame budgets for owner acceptance.
- Development version `0.12.0+12`; SQLite stays v8 because no persistence
  contract changed.

The full checked repository/owner checklist is in
`engineering/Release_Readiness.md`. Firebase and AI/subscription activation stay
in `engineering/Firebase_Integration.md` and
`engineering/AI_Coach_and_Subscriptions.md`.

## Validation Snapshot

- Dart formatting: pass.
- Flutter analyzer: pass, no issues.
- Flutter test suite: pass, 65 tests, including analytics contract, release
  guard, semantics, 48-pixel target, 320-pixel viewport, and 200% text.
- Backend core/provider/analytics: pass, 19 tests.
- Auth/Firestore/Functions callable emulator: pass, 2 end-to-end suites,
  including AI cache/quota and RevenueCat entitlement materialization.
- Firestore Rules emulator: pass, including owned AI read, cross-user denial,
  direct AI write denial, and private policy denial.
- Production npm audit: pass, zero vulnerabilities.
- Release metadata guard: pass for `0.12.0+12`.
- Android debug build and size budget: pass; version `0.12.0`, build `12`,
  minSdk 24, 169,726,077 bytes of the 199,229,440-byte budget.
- Android APK SHA-256:
  `68318dad45ae148b75972ef72bc59a52b77263fc26e57921f3bfb550d76130d2`.
- Hosted GitHub Actions: pass for quality/tests/emulators and Android artifact
  on [run #34752992038](https://github.com/fauzibinfaisal/ExamCoach/actions/runs/34752992038).
- iOS build/device/signing test: skipped by owner direction.
- Real Firebase/OpenAI/RevenueCat/store test: requires owner configuration.

## Next Steps

1. Start Web CBT W0/W1 in a new feature branch: audit Flutter Web versus a
   separate web frontend, record the architecture decision, threat-model the
   link flow, and create the implementation plan.
2. Keep real link/backend development on Firebase emulators until the owner is
   ready to enable billing and deploy a development environment.
3. Owner: complete the unchecked items in
   `engineering/Release_Readiness.md` in order; they require owner accounts,
   legal/product decisions, store authority, signing keys, or physical devices.
4. Keep `main` unchanged until the owner signs off a separate release candidate.
5. After acceptance, create `release/x.y.z`, select the first stable version,
   merge to `main`, and tag the exact released commit.

## Owner/External Actions Required

- Select/configure a Firebase development project and deployment credentials.
- Configure staged App Check, review valid traffic, then enable callable
  enforcement; never ship the debug provider.
- Approve Crashlytics privacy/retention and verify one symbolicated test crash.
- Select an OpenAI model/API key and approve per-plan daily quotas/cache TTL.
- Create RevenueCat/store products, offering, entitlement IDs, localized
  pricing, public Android SDK key, and server secret key.
- Execute real Android license-tester/Test Store purchase and refund/expiry
  scenarios. iOS stays deferred per owner direction.
- Approve production content, privacy/retention/deletion/refund/support policy,
  identifiers, signing, and store metadata.
- Require hosted CI checks in GitHub branch protection after their first run.
- Measure Android cold start/frame health on a selected physical baseline device.

## Known Limitations

- Recovery supports an empty local session store, not general multi-writer
  merge; one local database remains permanently bound to its first account.
- Sync is startup/reconnect-driven; OS background scheduling and dead-letter
  operator UI are pending.
- Subscription renewal/cancellation is refreshed on paywall load,
  purchase/restore, and bounded by stored expiry. A proactive RevenueCat webhook
  is not yet operational.
- App Check/Crashlytics code and gates exist, but real enforcement, alerting,
  privacy acceptance, physical performance evidence, legal links, and release
  signing remain owner/environment work.
- Emulator Functions use host Node 26 while deployment is pinned to Node 22;
  exact-runtime CI is pending.
- Firebase plugins still emit Flutter's future built-in Kotlin migration
  warning; the Android build currently passes.
- Prototype and generated questions remain development-only drafts.

## Governing Decisions

- Deterministic Dart learning output is authoritative; AI is explanation only.
- Quota, entitlement, AI provider, and AI cache are server-owned and
  authenticated; provider/RevenueCat secrets never enter Flutter.
- Store offering data supplies all product text/price; prices are not hard-coded.
- Analytics and operational logs are schema-bounded and privacy-minimized;
  telemetry activation never becomes a learning dependency.
- App Check is staged and additive to Auth, Rules, server authorization, quota,
  and entitlement validation.
- SQLite writes/outbox share transaction boundaries; cache failure cannot block
  learning or hide an already charged valid response.
- `main` is release-only, `develop` is integration, and normal work uses
  `feature/*`/`bugfix/*` pull requests.
- Pre-1.0 builds use `0.MINOR.PATCH+BUILD`; database schemas are versioned
  independently.
