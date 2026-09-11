# ExamCoach — AI Coach and Subscription Integration

## Status

Step 11 repository implementation is complete in development version
`0.11.0+11`. AI Coach, quota, local/server cache, trusted entitlement refresh,
RevenueCat offering/purchase/restore UI, and failure fallbacks are implemented
and locally/emulator tested. Production activation still requires owner-created
Firebase, OpenAI, RevenueCat, and store configuration; no credential, product,
price, quota, or model was invented or committed.

## Trust Boundary

```text
Deterministic local result
  → canonical structured context + SHA-256 key
  → authenticated callable Function
  → server policy + Firestore entitlement + atomic daily quota
  → unexpired same-context, same-capability server cache, or OpenAI Responses API
  → strict JSON Schema + server validation
  → owned Firestore cache + SQLite cache
  → AI Coach presentation
```

Scoring, answer correctness, weakness calculation, recommendation, and drill
selection remain deterministic Dart logic. AI can only explain those facts,
make an entitlement-allowed schedule, and motivate. It cannot override a result
or promise passing. When Firebase, policy, quota, provider, or network is
unavailable, the deterministic result remains visible; a valid local AI cache
can also remain readable.

## Mobile Behavior

- AI Coach opens from Home after a completed result and from the Result page.
- A canonical context contains the completed session, exam/test IDs, integer
  score percentage, top three deterministic weakness profiles, and the current
  deterministic recommendation.
- UTC timestamps use millisecond precision before hashing, matching JavaScript
  canonicalization.
- AI UI states cover no result, signed out, loading, ready, cached success,
  disabled provider/policy, exhausted quota, and safe failure.
- SQLite schema v8 stores authenticated AI responses by context key and expiry.
- Subscription UI reads the current RevenueCat offering. Titles, descriptions,
  periods, and localized prices come from the store; no price is hard-coded.
- Purchase and restore results do not directly grant premium capability. The
  app calls `refreshSubscriptionEntitlement`; only its server-verified result is
  displayed and persisted remotely.

## Backend Contracts

Callable Functions in `asia-southeast2`:

| Function | Authentication | Purpose |
|---|---|---|
| `getAiCoachStatus` | Required | Return server policy plan and UTC-day quota |
| `requestAiCoachInsight` | Required | Cache lookup, quota reservation, provider call, validation, and response |
| `refreshSubscriptionEntitlement` | Required | Fetch RevenueCat customer status and materialize the trusted plan |

Important Firestore paths:

```text
config/ai_coach_policy
users/{uid}/entitlements/current
users/{uid}/ai_usage/{YYYY-MM-DD}
users/{uid}/ai_requests/{contextKey}
users/{uid}/ai_insights/{contextKey}
```

Clients may read only their own `users/{uid}/**` tree and cannot write any of
these records. Functions use Admin SDK transactions. A same-context, unexpired,
capability-compatible server cache hit does not consume another quota unit. A
verified upgrade from Free to a study-plan-enabled tier regenerates the insight
instead of serving a less-capable cached result. A new generation reserves one
unit atomically; provider/validator failure releases the matching reservation.
Concurrent duplicate generation is refused, and an abandoned
reservation can be replaced after two minutes.

The policy document is validated server-side. It must include `free`; each plan
has a daily quota from 0 through 100 and a `study_plan_enabled` flag. The
repository template at `config/ai_coach_policy.example.json` is intentionally
disabled with zero quotas so activation requires an explicit product decision.

## Secrets and Runtime Configuration

Never place the OpenAI key or RevenueCat secret key in Flutter Dart defines.
Cloud Functions use two JSON secrets:

```text
AI_PROVIDER_CONFIG
REVENUECAT_SERVER_CONFIG
```

Expected shapes are shown in `functions/.secret.local.example`. The mobile app
uses only platform-specific RevenueCat public SDK keys:

```text
EXAMCOACH_REVENUECAT_ENABLED
EXAMCOACH_REVENUECAT_ANDROID_API_KEY
EXAMCOACH_REVENUECAT_IOS_API_KEY
```

The public-key placeholders are in
`config/firebase.dart-defines.example.json`. Local files matching
`config/firebase.*.json` and `functions/.secret.local` are ignored by Git.

## Owner Activation Checklist

These steps require accounts or product decisions and cannot be completed from
the repository alone:

1. Complete the Firebase development-project setup in
   `Firebase_Integration.md`; enable Auth and deploy Firestore Rules/Functions.
2. Choose an approved OpenAI model and decide daily quota values for `free`,
   `premium_1`, and `premium_2`. Copy the policy template into the Firestore
   document `config/ai_coach_policy`, set the chosen values, and enable it only
   after testing.
3. Set the provider secret with
   `firebase functions:secrets:set AI_PROVIDER_CONFIG`; enter JSON matching the
   example with the real API key and approved model.
4. Create a RevenueCat project and Android app for
   `id.examcoach.exam_coach`. Create the owner-approved store products,
   entitlement IDs, packages, and a current offering. Pricing stays in the
   store/RevenueCat dashboard.
5. Map RevenueCat entitlement IDs to `premium_1`/`premium_2`, then set
   `REVENUECAT_SERVER_CONFIG` using
   `firebase functions:secrets:set REVENUECAT_SERVER_CONFIG`. Use a server-only
   RevenueCat secret key and the JSON shape in the example.
6. Put the Android public SDK key in an ignored development Dart-define file,
   set `EXAMCOACH_REVENUECAT_ENABLED` to `true`, and run with
   `--dart-define-from-file`. Keep the iOS key disabled until iOS work resumes.
7. Deploy, create a Firebase test account, complete a tryout, and verify Free
   quota/cache behavior before testing a RevenueCat Test Store or Google Play
   license-tester purchase.
8. Verify purchase, app restart, restore, expiry/cancellation, plan downgrade,
   quota reset, provider outage, and an exhausted quota. Confirm deterministic
   result and recommendation remain usable in every failure case.

RevenueCat configuration requires an account, project, products, and
entitlements before real purchase testing. Its Flutter SDK must be configured
with platform public keys, while server REST keys remain secret. OpenAI
structured output is requested through the Responses API with `store: false`.

## Local Validation

Core and Flutter checks:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
npm --prefix functions test
```

Full callable emulator validation uses deterministic provider stubs and never
contacts OpenAI or RevenueCat:

```bash
env JAVA_HOME=/usr/local/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
  EXAMCOACH_AI_EMULATOR_STUB=true \
  EXAMCOACH_SUBSCRIPTION_EMULATOR_STUB=true \
  npx --yes firebase-tools@15.8.0 emulators:exec \
  --project examcoach-test --only auth,firestore,functions \
  "npm --prefix functions run test:callable"
```

The emulator-only stubs require both `FUNCTIONS_EMULATOR=true` (set by Firebase)
and the explicit ExamCoach flag. They cannot activate in deployed Functions.
For local real-provider testing, copy `functions/.secret.local.example` to the
ignored `functions/.secret.local` and replace placeholders; do not commit it.

## Known Limitations

- Renewal/cancellation freshness is updated when the subscription page loads or
  purchase/restore completes. Stored expiry fails closed to Free; a RevenueCat
  webhook for proactive refresh is deferred until the owner selects a plan that
  supports it and completes an operational security review.
- A real Google Play purchase needs Play Console product setup and a license
  tester. iOS purchase/signing remains skipped by owner direction.
- Quotas, product IDs, prices, entitlement IDs, provider model, retention, and
  refund/support language remain owner decisions.
- App Check, production observability, legal links, accessibility/performance
  gates, and store-release readiness belong to Step 12.

## Primary References

- OpenAI Responses API create method:
  <https://developers.openai.com/api/reference/resources/responses/methods/create>
- Firebase secret parameters:
  <https://firebase.google.com/docs/functions/config-env#secret_parameters>
- RevenueCat Flutter installation:
  <https://www.revenuecat.com/docs/getting-started/installation/flutter>
- RevenueCat SDK configuration:
  <https://www.revenuecat.com/docs/getting-started/configuring-sdk>
- RevenueCat customer/entitlement status:
  <https://www.revenuecat.com/docs/customers/customer-info>
- RevenueCat REST API v1:
  <https://www.revenuecat.com/docs/api-v1>
