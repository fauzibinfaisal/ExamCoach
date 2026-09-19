# ExamCoach — Web Platform Architecture

Decision: [DEC-014](../DECISION_LOG.md). Audit baseline: `9746833`, 2026-09-19.
Product authority: [Web CBT PRD](../product/Web_Linked_Mock_Test_PRD.md).

## Evidence and alternatives

| Concern | Flutter Web in current package | Separate React/TypeScript web |
|---|---|---|
| Storage | `bootstrap.dart` calls `ExamCoachDatabase.openDefault`; sqflite is native. Web needs another factory, WASM/worker setup and browser migration tests. Fallback memory is not durable recovery. | Explicit memory-only W1; IndexedDB drafts later, server-owned recovery. No dependency on SQLite. |
| Firebase | Core/Auth/Functions have web adapters, but current `FirebaseRuntimeConfig.optionsFor` selects Android/iOS IDs, App Check has mobile providers, and Crashlytics is referenced during initialization. Requires separate web setup and telemetry handling. | W1 has no Firebase SDK or real project. Future profile auth and same-origin session HTTP adapters are separate. |
| RevenueCat | SDK now supports web, but repository configuration has Android/iOS keys and platform checks only; browser-on-mobile could select a mobile key. Requires explicit web billing setup, not reuse by assumption. | Purchases excluded; link access never conveys entitlement. No new billing product. |
| Routing | GoRouter supports web; no web target exists here, and mobile question routes assume Cubits/local state. Hosting rewrites and token cleanup still needed. | Browser paths, real anchors, SPA fallback, native focus; only two W1 pages plus safe 404. |
| Secure cookies | Neither framework can set/read HttpOnly cookies in JS. Needs server HTTP endpoints, same-origin transport and CSRF defense. | Same constraint; do not use a Firebase Auth token as link-session authority. |
| Question assets | `pubspec.yaml` bundles `assets/question_bank/`; question models/seed contain correct option and explanation. Shipping this bundle exposes keys, including drafts. | Do not import mobile assets. Later gateway sends published, fingerprint-bound question projections without keys/explanations. |
| Domain reuse | Pure Dart engine is reusable, but browser execution is untrusted. Reuse does not solve trusted scoring. | Share contracts, retain Dart as the single algorithm implementation. Extract package with parity tests before trusted finalization. |
| Accessibility/UI | Flutter can implement accessible web UIs, but requires web-specific semantics/keyboard verification. | Native headings, links, buttons, skip link and CSS fit text-heavy desktop CBT. Still requires browser/screen-reader QA. |

The choice is an engineering judgement based on these repository boundaries,
not a claim that Flutter cannot run on the web. A separate Flutter package would
isolate bootstrap too, but offers limited immediate reuse for these two pages.

## Repository and ownership

```text
lib/, test/, android/, ios/      existing mobile app; unchanged in W1
functions/                      existing Node Firebase backend
apps/web/                       React/TypeScript/Vite client, own npm lockfile
contracts/web-cbt/               versioned language-neutral response schema
packages/learning_domain/       planned extraction, not created in W1
services/learning_authority/    planned Dart runtime, not created in W1
```

No root npm workspace is needed to relocate existing systems. CI invokes each
package explicitly. Web starts at `0.1.0`; capability milestones increment minor,
compatible fixes increment patch, and CI SHA identifies builds. Schema versions,
mobile `0.12.0+12`, and SQLite v8 remain independent. No stable release/tag.

## Trust and deterministic reuse

```text
Mobile Auth → Functions create/revoke → private Firestore link/attempt records
Browser → same-origin session gateway → Firestore transactions
                                      → private Dart learning authority
                                         (same package as mobile)
```

Only the future trusted service loads answer keys, recomputes correctness,
score, weakness and recommendation, and returns versioned deterministic output.
It must validate unique/exact question coverage, option membership, fingerprint,
algorithm version and owned history; calling the existing scoring function
alone is insufficient input validation. AI is never in this path. Golden tests
must compare mobile and server outputs for skips, edits, timing, repeated
history and boundary cases before W4. No TypeScript scoring engine is permitted.

Current sync only restores an empty mobile database; W4 must add a scoped,
idempotent inbound completed-attempt import into an existing owned history.
Do not claim the current recovery endpoint already supports live web-result sync.

The proposed private Dart runtime adds packaging/IAM/latency overhead. Prototype
it locally alongside the emulators; no Cloud Run instance is created in W1.
If runtime feasibility changes, revise DEC-014 before adding another authority.

## Browser lifecycle

W1 `/profile` contains a sample profile and clearly states there is no signed-in
web account. `/mock-test` defaults to invalid/unavailable. A loopback-only,
explicit preview mode selects non-secret fixture labels; labels are not tokens.
The seven UI states are validating, ready, claimed, expired, revoked, completed,
and invalid. Claimed means bound elsewhere/unknown ownership, so it contains no
tryout identity. Same-browser recovery later uses the cookie/session endpoint,
not a claimed URL response. Terminal responses carry no account or tryout data.
No W1 state can open questions or mutate an attempt.

W1 stores no browser data and registers no service worker. URL query/fragment
input is removed before application rendering; no real capability is accepted.
Future token intake uses `/mock-test#<opaque-token>` (fragment avoids request
logs/referrers), cleans history synchronously, and sends it once in a redacted
POST body. Never put tokens into path/query, storage, errors or telemetry.
Resume uses only the HttpOnly session cookie. A pre-claim refresh can require
reopening the original mobile link; post-claim refresh must recover safely.

W4 IndexedDB is a disposable, attempt-scoped queue of answer drafts with bounded
retention, cleared on terminal/revocation/account change. It cannot extend timers,
authorize sessions or override acknowledged server revisions. Private browsing,
storage eviction and disabled storage must degrade to explicit network/recovery
feedback; no silent claim takeover.

## Firebase and hosting boundary

W1's fake repository makes no requests. Existing Firebase tests still run on
Auth 9099, Functions 5001 and Firestore 8080 using `demo-examcoach`. W2 introduces
create/revoke under authenticated mobile context; W3 introduces browser HTTP
endpoints behind a same-origin local proxy, restricted to loopback/demo IDs.
Neither an emulator outage nor missing config may fall back to production.

Later static hosting target: Firebase Hosting with SPA rewrites and security
headers; `/api/**` goes to Functions before the SPA fallback. Hosting forwards
only `__session`; use a host-only cookie with no Domain, Path=/, HttpOnly, Secure,
SameSite=Strict and lifetime capped by server deadlines. Reject duplicate or
malformed cookies, validate Origin/Fetch Metadata and CSRF on mutations, and
return private/no-store on all capability/session responses. Test this topology
under HTTPS before W5; HTTP emulator behavior does not prove Secure-cookie
behavior. Do not enable caching or third-party scripts on token intake.

Target desktop QA widths: 1024, 1280 and 1440 CSS pixels; also test 768 tablet
and 375 reflow. Chromium is the W1 automated baseline; Firefox/WebKit and real
screen readers belong to W5 before claiming browser support.

## Primary references checked during audit

- [sqflite platform support](https://pub.dev/packages/sqflite): native platforms;
  experimental web uses a separate adapter.
- [Flutter web FAQ](https://docs.flutter.dev/platform-integration/web/faq): web
  tradeoffs and application-oriented rendering.
- [FlutterFire setup/platforms](https://firebase.google.com/docs/flutter/setup):
  platform configuration and plugin matrix.
- [RevenueCat Flutter web support](https://www.revenuecat.com/blog/engineering/flutter-sdk-web-support):
  support exists; web billing still requires its own configuration.
- [Firebase Hosting cookies](https://firebase.google.com/docs/hosting/manage-cache):
  special `__session` forwarding through dynamic rewrites.
- [Set-Cookie semantics](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Set-Cookie):
  HttpOnly, Secure, SameSite and host scoping.
