# ExamCoach Project Status

## Current Phase

Step 11 repository implementation is complete. ExamCoach now has structured AI
Coach output, server-owned quota and cache, RevenueCat offering/purchase/restore,
and trusted backend entitlement refresh while preserving the deterministic,
offline-first learning loop. The next milestone is Step 12 product analytics,
accessibility, performance, CI, observability, and release readiness.

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
| 12 | Product analytics, accessibility, performance, CI, and release readiness | Next |

Current position: **Step 11 of 12 complete (92%)**. Current development version
is `0.11.0+11`; SQLite schema is v8. Work is on
`feature/structured-ai-coach` for protected integration into `develop`.
`main` remains release-only and unchanged.

## Step 11 Delivered

- Canonical version-1 learning context with recursive sorted JSON, SHA-256 key,
  integer/basis-point metrics, millisecond UTC normalization, and server
  revalidation before quota/provider work.
- AI Coach Cubit/page reachable from Result and Home, including deterministic
  fallback, no-result, signed-out, loading, ready, cached, quota-exhausted,
  disabled, and failure states.
- Authenticated status/generation callables with configurable Free/Premium plan
  policy, UTC-day quota, atomic reservation/release, duplicate-in-flight guard,
  expiry, and capability-aware same-context server cache hits. Upgrading from a
  Free result to a study-plan-enabled tier forces regeneration before the paid
  capability is shown.
- OpenAI Responses API adapter with server-only JSON secret, strict JSON Schema,
  compact instructions, output ceiling, `store: false`, hashed safety ID,
  prompt cache key, and server output/guarantee validation.
- SQLite schema v8 `ai_coach_insights` cache tied to the completed source
  session; expired cache is deleted and cache/analytics failure cannot block
  valid coaching or deterministic learning.
- RevenueCat Flutter integration for current offering, localized store prices,
  purchase, restore, authenticated Firebase UID identity, and safe disabled
  configuration.
- Backend RevenueCat customer lookup and mapping of active entitlements to
  policy plan IDs. Only backend materialization controls AI plan/quota; client
  purchase state is not authority.
- Android Billing permission, ignored local-secret/runtime templates, Free-safe
  policy template, analytics events, architecture/setup/acceptance guide, and
  pre-1.0 version `0.11.0+11`.

Full setup, protocol, and manual acceptance instructions are in
`engineering/AI_Coach_and_Subscriptions.md`. Step 10 Firebase setup remains in
`engineering/Firebase_Integration.md`.

## Validation Snapshot

- Dart formatting: pass.
- Flutter analyzer: pass, no issues.
- Flutter test suite: pass, 59 tests.
- Backend core/provider: pass, 17 tests.
- Auth/Firestore/Functions callable emulator: pass, 2 end-to-end suites,
  including AI cache/quota and RevenueCat entitlement materialization.
- Firestore Rules emulator: pass, including owned AI read, cross-user denial,
  direct AI write denial, and private policy denial.
- Production npm audit: pass, zero vulnerabilities.
- Android debug build: pass; version `0.11.0`, build `11`, minSdk 24,
  169,220,184 bytes.
- Android APK SHA-256:
  `1b464d139c259ae63d221190df5b5849f543f2baef0dd45d3854c04f2f442e64`.
- iOS build/device/signing test: skipped by owner direction.
- Real Firebase/OpenAI/RevenueCat/store test: requires owner configuration.

## Next Steps

1. Owner: follow `engineering/AI_Coach_and_Subscriptions.md` to choose quotas,
   OpenAI model, RevenueCat products/entitlements/prices, create secrets, and
   run the Android test-purchase acceptance plan.
2. Owner: complete the Firebase development-project setup and two-device
   recovery test in `engineering/Firebase_Integration.md` if not already done.
3. Have a real human review and publish production question content.
4. Step 12: add CI-required checks, accessibility semantics and device checks,
   performance budgets, Crashlytics/structured observability, App Check,
   analytics dashboards, and release identifiers/signing/store readiness.
5. Decide whether the selected RevenueCat plan and operations warrant a signed
   webhook for proactive renewals/cancellations; current backend refresh plus
   stored expiry fails closed safely.

## Owner/External Actions Required

- Select/configure a Firebase development project and deployment credentials.
- Select an OpenAI model/API key and approve per-plan daily quotas/cache TTL.
- Create RevenueCat/store products, offering, entitlement IDs, localized
  pricing, public Android SDK key, and server secret key.
- Execute real Android license-tester/Test Store purchase and refund/expiry
  scenarios. iOS stays deferred per owner direction.
- Approve production content, privacy/retention/deletion/refund/support policy,
  identifiers, signing, and store metadata.

## Known Limitations

- Recovery supports an empty local session store, not general multi-writer
  merge; one local database remains permanently bound to its first account.
- Sync is startup/reconnect-driven; OS background scheduling and dead-letter
  operator UI are pending.
- Subscription renewal/cancellation is refreshed on paywall load,
  purchase/restore, and bounded by stored expiry. A proactive RevenueCat webhook
  is not yet operational.
- App Check, email verification policy, account deletion, remote retention,
  production observability, accessibility/performance gates, legal links, and
  release signing remain Step 12/owner work.
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
- SQLite writes/outbox share transaction boundaries; cache failure cannot block
  learning or hide an already charged valid response.
- `main` is release-only, `develop` is integration, and normal work uses
  `feature/*`/`bugfix/*` pull requests.
- Pre-1.0 builds use `0.MINOR.PATCH+BUILD`; database schemas are versioned
  independently.
