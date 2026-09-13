# ExamCoach — Step 12 Release Readiness

## Status

Repository implementation targets development version `0.12.0+12`. It adds
repeatable CI, analytics privacy contracts, accessibility regression coverage,
an Android artifact-size budget, opt-in Firebase App Check, opt-in Crashlytics,
and structured backend operational logs.

This does **not** make the app a production `1.0.0` release. Production remains
blocked until the owner completes the unchecked external actions below. `main`
remains release-only.

## Repository Checklist

- [x] GitHub Actions runs formatting, metadata validation, Flutter analysis,
  all Flutter tests, Functions tests, npm audit, Firestore Rules emulator, and
  authenticated callable emulator tests.
- [x] CI builds an Android debug APK, rejects artifacts above 190 MiB, and keeps
  the APK as a 14-day workflow artifact.
- [x] Pre-1.0 metadata guard rejects malformed/stable versions and non-monotonic
  development build numbers.
- [x] Analytics event names and properties are allow-listed independently in
  Flutter and Functions; unsupported, nested, oversized, or privacy-risk data
  is rejected.
- [x] Backend operational logs use a truncated SHA-256 subject hash and bounded
  dimensions. They never log raw UID, prompt, AI output, answers, prices,
  payment data, or credentials.
- [x] Firebase App Check client activation is opt-in. Production providers are
  Play Integrity on Android and App Attest with DeviceCheck fallback on Apple.
- [x] The App Check debug provider is separately opt-in and defaults off.
- [x] Callable enforcement uses the non-secret Functions environment flag
  `EXAMCOACH_ENFORCE_APP_CHECK`, which defaults to `false` for staged rollout.
- [x] Crashlytics collection and global Flutter/asynchronous error handlers are
  opt-in and default off.
- [x] The primary learning flow has automated screen-reader semantics,
  48-pixel target, 320-pixel viewport, and 200% text-scaling coverage.
- [x] Session controls and taxonomy tags adapt at large text sizes instead of
  clipping horizontally.
- [x] iOS build/testing remains explicitly deferred by owner direction.

## Automated Commands

Run from the repository root:

```bash
dart format --output=none --set-exit-if-changed lib test tool
dart run tool/check_release_metadata.dart
flutter analyze
flutter test --coverage
npm --prefix functions test
npm --prefix functions audit --omit=dev --audit-level=high
flutter build apk --debug
dart run tool/check_apk_budget.dart build/app/outputs/flutter-apk/app-debug.apk
```

Emulator commands are defined in `.github/workflows/ci.yml` so CI and local
validation use the same Firebase CLI version and explicit local stubs.

## Performance Budgets

| Signal | Budget | Gate |
|---|---:|---|
| Android debug APK | ≤ 190 MiB | Automated in CI |
| Deterministic result interaction | no network/provider dependency | Automated architecture/tests |
| Cold start to usable local Home | ≤ 2.5 seconds on selected Android baseline | Owner physical-device profile |
| Tryout answer interaction | no visible frame stall; <1% slow/frozen frames in Play vitals | Owner internal-test monitoring |
| Callable AI timeout | ≤ 60 seconds | Enforced server configuration |
| Entitlement refresh timeout | ≤ 30 seconds | Enforced server configuration |

Wall-clock mobile performance is intentionally not asserted in shared-host unit
tests because that produces flaky results. Physical-device profile measurements
and Play vitals are the release evidence for startup and frame budgets.

## Owner-Only Actions — Complete in Order

These actions require your accounts, legal decisions, physical devices, or
store authority. Codex cannot truthfully complete them without those resources.

### 1. GitHub protection

- [ ] Open repository Settings → Branches/Rulesets.
- [ ] Require pull requests for `develop` and `main`.
- [ ] Require the checks `Quality, tests, and emulators` and
  `Android debug artifact` after they appear on the first Step 12 PR.
- [ ] Keep direct pushes and force pushes disabled for both branches.

### 2. Firebase development environment

- [ ] Complete `Firebase_Integration.md` using a non-production project.
- [ ] Deploy Functions/Rules while `EXAMCOACH_ENFORCE_APP_CHECK=false`.
- [ ] Confirm authentication, sync, recovery, AI, and entitlement tests in the
  development project before changing enforcement.

### 3. App Check staged rollout

- [ ] Register the Android app and Play Integrity provider in Firebase Console.
- [ ] For local/dev builds only, set `EXAMCOACH_APP_CHECK_DEBUG_PROVIDER=true`,
  capture the generated debug token, and register that token in Firebase.
- [ ] Set `EXAMCOACH_APP_CHECK_ENABLED=true` and verify valid requests arrive.
- [ ] Review App Check metrics for legitimate unsupported clients.
- [ ] Set the Functions environment flag
  `EXAMCOACH_ENFORCE_APP_CHECK=true` only after valid development traffic is
  confirmed.
- [ ] Never enable the debug provider in a production build.

### 4. Crashlytics and privacy

- [ ] Approve privacy/retention/deletion language for crash and device metadata.
- [ ] Finish native Firebase app configuration and symbol upload setup using
  FlutterFire/Firebase guidance for the selected project.
- [ ] Set `EXAMCOACH_CRASHLYTICS_ENABLED=true` only in the approved build.
- [ ] Send one deliberate non-production test crash and verify symbolicated
  delivery in Firebase Console before relying on alerts.
- [ ] Configure alerts for fatal regressions, sync failures, AI failure rate,
  quota exhaustion, entitlement verification, and analytics backlog.

### 5. Android internal release

- [ ] Replace debug signing with an owner-controlled upload/release key stored
  outside Git.
- [ ] Choose the final Android application ID; the current ID remains
  provisional.
- [ ] Create a signed Android App Bundle and upload it to an internal track.
- [ ] Complete Play Console data safety, privacy policy, support, refund, and
  subscription disclosures.
- [ ] Run a real license-tester purchase, restore, cancellation, expiry,
  downgrade, offline, and refund scenario.
- [ ] Measure cold start and frame health on the selected baseline device.

### 6. Content and release approval

- [ ] A named human reviews and publishes production question packs.
- [ ] Product owner approves AI model, quotas, cache TTL, plans, localized
  prices, support policy, and cost alert thresholds.
- [ ] Complete the full learning loop on at least one clean Android device and
  one upgraded database installation.
- [ ] Resume and complete iOS signing/device/App Check/purchase testing before
  any iOS release.
- [ ] Only after every required item passes: create a `release/x.y.z` branch,
  choose the first stable version, merge to `main`, and tag that exact commit.

## Required Dart Defines

All three flags default to `false`:

```json
{
  "EXAMCOACH_APP_CHECK_ENABLED": false,
  "EXAMCOACH_APP_CHECK_DEBUG_PROVIDER": false,
  "EXAMCOACH_CRASHLYTICS_ENABLED": false
}
```

Use `config/firebase.dart-defines.example.json` as the template. Never commit a
real project-specific copy, debug token, signing key, provider secret, or store
server credential.

Use `functions/.env.example` as the Functions flag template. Copy it to the
Firebase project-specific environment file required by your deployment process;
do not change enforcement to `true` before the staged App Check checks pass.

## Failure Policy

- Missing Firebase configuration keeps deterministic local learning available.
- Enabled but invalid App Check/Crashlytics configuration fails Firebase startup
  closed instead of claiming protected telemetry or remote access.
- Analytics rejection never blocks learning, AI, or purchase state transitions.
- Crash reporting never receives explicit email, raw UID, answer text, prompts,
  payment data, or secrets from ExamCoach code.
- App Check is an abuse signal and request-attestation layer, not a replacement
  for Authentication, Firestore Rules, server authorization, quota, or trusted
  entitlement verification.

## Official References

- Firebase App Check for Flutter:
  <https://firebase.google.com/docs/app-check/flutter/default-providers>
- App Check enforcement for callable Functions:
  <https://firebase.google.com/docs/app-check/cloud-functions>
- Firebase Crashlytics for Flutter:
  <https://firebase.google.com/docs/crashlytics/get-started?platform=flutter>
- Flutter accessibility testing:
  <https://docs.flutter.dev/ui/accessibility-and-internationalization/accessibility>
- GitHub protected branches:
  <https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches>
