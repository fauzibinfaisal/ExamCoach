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
development version is `0.13.0+13`; SQLite schema remains v8. Step 12 was
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

W1 and W2 repository implementation is complete: **W2 of W5 (40% of the web
implementation track)**. W1 was merged through [PR #16](https://github.com/fauzibinfaisal/ExamCoach/pull/16)
at `8d17cfd`; W2 integration and hosted checks are tracked in
[PR #17](https://github.com/fauzibinfaisal/ExamCoach/pull/17), requiring every CI gate to pass.
The completed mobile roadmap remains **12/12 (100%)**. Mobile is now `0.13.0+13`,
SQLite v8; no database migration or learning algorithm change.

DEC-014 selects one repository with separate applications: mobile at root,
React/TypeScript/Vite web at `apps/web`, and Node Functions at `functions`.
The owner explicitly confirmed this monorepo boundary during W1. Web is `0.1.0`
with its own dependencies, lockfile, tests, build and versioning. W2 adds mobile
link management through a separate repository/Cubit and authenticated callables.

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

Delivered W2 scope (demo emulators only): authenticated create/revoke/management,
256-bit one-time token, cryptographic hash-only private storage, server-owned
12-hour expiry, transaction/replay/concurrency protection, per-UID development
rate limits, copy-once transient mobile state and strict response validation.
Full published packs now deny direct client reads. Synthetic manifests do not
claim human-approved publication. See [W2 lifecycle](engineering/Web_Link_Management.md)
and [Rules audit](engineering/Web_Link_Rules_Audit.json).

Browser claim, question delivery, autosave, trusted scoring, result import and
hosting remain **W3–W5, not implemented**. The Dart learning
engine stays the single implementation; extraction and a private trusted Dart
runtime require parity tests before W4. Current mobile empty-device recovery
must not be mistaken for web-result import into an existing history.

Read [web architecture](architecture/Web_Platform_Architecture.md),
[delivery plan](engineering/Web_Mock_Test_Delivery_Plan.md), and
[threat model](engineering/Web_Link_Security_Threat_Model.md). No billing,
Firebase project, deployment, iOS work or stable release was performed.

## W2 Validation Snapshot

- Dart formatting, release metadata and analyzer: PASS; Flutter tests: 73 PASS.
- Functions tests: 23 PASS; production dependency audit: zero vulnerabilities.
- Demo emulators: one expanded Rules suite and four callable tests PASS,
  including token/log canaries, races, rates, ownership and permanent expiry.
- Web regression: formatting/lint/types/build, 43 unit/component and 16 Chromium
  tests PASS; dependency audit: zero vulnerabilities.
- Android debug build/budget: PASS, 169,747,493 bytes; mobile `0.13.0+13`.
- APK SHA-256: `12cf42a1698e671c9354bc0ff6489fa2b1087ba9dd2c049af2a60b8974615200`.
- iOS, physical-device QA, live backend, browser claim and hosting remain deferred.

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

1. Complete W2 integration into `develop` only after every hosted check passes.
2. Start W3 from updated develop: transactional browser claim, secure same-origin
   session/cookie and CSRF boundary, same-browser recovery and CBT workspace.
3. Implement safe question projection from immutable human-approved content;
   never reopen direct reads to answer-bearing published packs. Synthetic W2
   manifests are not production publication evidence.
4. Preserve DEC-013/014/015, and defer autosave/scoring/result import to W4.
5. Owner external decisions remain in the delivery plan. Keep billing, live
   deployment, iOS and main/release work outside this development scope.

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
