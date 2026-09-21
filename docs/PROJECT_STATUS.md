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

The W1 foundation is implemented: **W1 of W5 (20% of the web implementation
track)**, with W0 preparation complete. Hosted integration validation is pending.
The completed mobile roadmap remains **12/12 (100%)** at `0.12.0+12`, SQLite v8.

DEC-014 selects one repository with separate applications: mobile at root,
React/TypeScript/Vite web at `apps/web`, and Node Functions at `functions`.
The owner explicitly confirmed this monorepo boundary during W1. Web is `0.1.0`
with its own dependencies, lockfile, tests, build and versioning. No mobile
runtime or deterministic algorithm changed.

Delivered W1 scope:

- Desktop profile shell with explicit sample/signed-out context.
- `/mock-test` landing with validating, ready, claimed, expired, revoked,
  completed and invalid states; terminal/claimed responses expose no metadata.
- Strict versioned response schema, time/shape checks and repository interface.
- Memory-only fixtures behind explicit preview mode and exact loopback host;
  default build denies access. No W1 route can open questions.
- URL cleanup, native keyboard navigation, responsive CSS and accessibility
  tests. No browser persistence, telemetry, cookie or real token is created.
- Separate web CI and existing Flutter/backend/emulator/Android gates.

Real link creation, browser claim, question delivery, autosave, trusted scoring,
result import and hosting remain **W2–W5, not implemented**. The Dart learning
engine stays the single implementation; extraction and a private trusted Dart
runtime require parity tests before W4. Current mobile empty-device recovery
must not be mistaken for web-result import into an existing history.

Read [web architecture](architecture/Web_Platform_Architecture.md),
[delivery plan](engineering/Web_Mock_Test_Delivery_Plan.md), and
[threat model](engineering/Web_Link_Security_Threat_Model.md). No billing,
Firebase project, deployment, iOS work or stable release was performed.

## W1 Validation Snapshot

- Web Prettier, ESLint, TypeScript and default/fixture builds: PASS.
- Web unit/component tests: 43 PASS; Chromium browser tests: 16 PASS.
- All seven link states, terminal/claimed metadata redaction, default-closed
  build, URL cleanup, no browser persistence, keyboard navigation, axe checks,
  five viewport widths and 200% text: PASS.
- Flutter formatting/analyzer/metadata guard and 65 tests: PASS.
- Functions 19 tests and one Rules/two callable emulator suites: PASS on Node 22.
- npm audits for Functions production and all web dependencies: zero findings.
- Android debug build/budget: PASS, 169,723,345 bytes (limit 199,229,440).
- Real services, real link security and iOS: not in W1 scope.

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

## Previous Mobile Validation Snapshot

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

1. Complete W1 hosted CI and integrate only into `develop` after every gate passes.
2. Start W2 on a new feature branch: authenticated mobile create/revoke,
   server-owned 12-hour expiry and scope, hash-only token storage and emulator
   abuse/ownership tests. Use only `demo-examcoach` and local provider stubs.
3. Preserve DEC-013 product behavior and DEC-014 domain boundaries; do not
   implement claim/workspace/finalization as incidental W2 additions.
4. Owner: complete the web delivery plan's external checklist when ready for
   hosted testing; billing and real deployment remain deferred.
5. Keep `main` release-only. No `1.0.0` or iOS work without separate approval.

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
- W1 emulator validation uses isolated Node 22, matching Functions deployment;
  the machine default remains Node 26, so select the runtime explicitly.
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
