# ExamCoach — Web Link Security Threat Model

Baseline: DEC-013 product contract and DEC-014 architecture, 2026-09-19.
W1 implements a non-authoritative UI preview only. The controls below are future
requirements unless explicitly marked W1. A passing shell test is not evidence
of token entropy, transactional claims, production cookies or replay defense.

## Assets, actors and boundaries

Protect raw capability/session credentials, owner identity, published content
keys, answers, server deadlines and the unique deterministic result. Threats
include a link recipient, another browser/tab, unauthenticated attacker,
malicious client, compromised script and accidental telemetry collection.
Mobile Auth, untrusted browser, HTTPS gateway, Admin SDK/Firestore, and private
Dart scoring runtime are separate boundaries. Admin SDK bypasses Rules, so
server authorization and transaction invariants remain mandatory.

| Threat | Required control and acceptance test | Delivery |
|---|---|---|
| Guess/enumerate tokens | Server CSPRNG 256-bit capability; keyed/cryptographic hash only at rest; bounded uniform denials and rate limits. Test malformed, random, oversized input and throttling without token echo. | W2/W3 |
| Spoof owner or entitlement | Derive UID from verified Auth, authorize published tryout/fingerprint, reject forged owner; capability grants no profile/history/billing access. | W2 |
| Leak via URL/logs/storage | Fragment-only intake, synchronous history cleanup, no-referrer, no third-party resources; redact request bodies/errors; prohibit raw token persistence, analytics, crash reports and screenshots. Scan logs with synthetic canary during emulator tests. W1 discards incoming URL data and has no telemetry/storage. | W1 boundary; W2/W3 secure transport |
| Two browsers race/steal claim | Atomic compare-and-set on owner/tryout/fingerprint/session tuple; first claim installs hashed session binding; copied token cannot rebind. Test simultaneous claims, tab races, lost response, refresh and blocked cookies. | W3 |
| Fixation, XSS, CSRF, subdomain cookies | Fresh server session secret, host-only HttpOnly Secure SameSite=Strict cookie; strict Origin/Fetch Metadata + CSRF; reject ambiguous cookies; restrictive CSP and no untrusted HTML. Hosting requires `__session`; verify HTTPS rewrite forwarding. | W3/W5 |
| Client clock/timer manipulation | Server createdAt+12h exact unclaimed expiry; no start unless duration+grace fits; active deadline=min(exam deadline, link expiry). Revocation checked on every read/write. Client countdown is presentation only. | W2–W4 |
| Terminal link replay | Completed/expired/revoked/timeout never reactivate. Server content/answer/session endpoints all deny; replacements get new tokens. UI hides all metadata for denied statuses. | W1 UI; W2–W4 authority |
| Duplicate/lost final submit | Stable attempt id, frozen evidence digest, versioned deterministic computation; transaction commits one result plus terminal link. Same retry returns same result only to authorized session; changed evidence conflicts. Test concurrent retries/revoke/timeout. | W4 |
| Tamper score/questions | No answer keys in static web assets. Server loads approved immutable fingerprint and exact question set; Dart recomputes score/weakness/recommendation. Golden parity tests and forged-answer tests. AI excluded. | W4 |
| Offline/evicted drafts | Server revisions win, scoped IndexedDB queue contains no credentials, bounded retention, explicit unsaved indicator. Never extend deadline or fabricate success. | W4 |
| Auth/profile privilege confusion | Link grants only one attempt. Normal profile login is a separate principal; denied link pages expose no owner/tryout. W1 profile is visibly sample data. | W1 onward |
| Quota/DoS/cost | Bounded payloads, rate limits per principal and coarse network signal, abuse budget, no automatic AI call. Retention and threshold values need owner review before hosting. | W2/W5 |

## Session and terminal rules

Raw link token is returned once to authenticated mobile memory. Clipboard/share
are user-directed disclosure; no persistence or analytics capture in mobile.
The browser keeps it only transiently for validation/claim and removes it from
history immediately. No fake UUID/fixture label may become an auth credential.
The gateway stores hashes only, never sends UID or internal IDs in link URLs,
and never reveals tryout details for invalid/claimed-elsewhere/terminal links.

Same-browser resume uses the session cookie and rechecks deadlines/revocation.
A lost claim response must be recoverable without reassigning browser ownership;
implement and race-test that handshake in W3. No device fingerprint or localStorage
flag can authorize recovery. Clearing cookies requires owner revoke/replacement,
not a silent takeover path. Multiple tabs in the same browser still need revision
conflict handling.

Timeout follows the PRD terminal policy and cannot reopen an attempt. A future
server may finalize a timed-out attempt under the approved exam rules, but W1
introduces no timeout scoring policy. Terminal URL pages remain redacted even
when a separate authenticated session/result endpoint can return owned results.

## W1 evidence and residual risk

Automated contract/UI/browser tests must cover all seven states, metadata
redaction, unknown response rejection, opt-in loopback preview, URL cleanup,
keyboard access, refresh and no questions/start capability for terminal states.
The fake has no claim/submit methods, no real credentials and no persistence.
Production build must ignore fixture parameters and stay closed.

W1 does not mitigate a real token theft because no real-token service exists.
Server tests, HTTPS cookie tests, production header review, independent security
review and owner privacy/retention approval are release prerequisites in W5.
