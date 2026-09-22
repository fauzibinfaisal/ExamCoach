# ExamCoach — W2 Mobile Link Management

Status: implemented for local demo emulators only; integration and hosted checks
are tracked in [PR #17](https://github.com/fauzibinfaisal/ExamCoach/pull/17). W1 was merged through PR #16
at `8d17cfd`. W2 adds mobile `0.13.0+13`; SQLite v8 and web `0.1.0` are unchanged.
See DEC-015, the [delivery plan](Web_Mock_Test_Delivery_Plan.md), and
[security audit](Web_Link_Rules_Audit.json).

## Boundaries and mobile behavior

Home → **Kerjakan di laptop** loads the authenticated owner's available tryouts
and latest link per tryout. It never starts a local learning attempt. Create,
explicit copy-once, refresh and revoke are implemented. The URL is not rendered
as text, placed in a route, persisted in SQLite/preferences, or emitted through
Cubit states/analytics. Copy is a deliberate disclosure to the OS clipboard;
clipboard history/synchronization and its retention are outside app control.
Memory references are cleared after copy, refresh, revoke, navigation/disposal,
backgrounding or account change. Late responses are dropped using an account
and lifecycle generation check. No claim about secure memory zeroization is made.

A lost create response is deliberately unrecoverable as a raw token. Refresh
shows the server record; revoke it and issue a replacement. An API retry with
the same request ID returns metadata only. The mobile UI does not automatically
retry creation; it disables double taps and directs ambiguous failures to refresh.
The expiry shown on mobile is the server timestamp rendered in the device's
local timezone; it is not authorization. Refresh reads authoritative status.

The current browser safely refuses real tokens. **Opening the link does not yet
start a CBT**: claim, cookies, resume and question projection belong to W3;
autosave, scoring and mobile result import belong to W4. No scoring/AI code changed.

## Callable contract v1

Region: `asia-southeast2`. All requests require verified Firebase Auth and
`protocolVersion: 1`; unknown keys, wrong types, paths and oversized identifiers
are rejected. UID, clocks, lifetime, session identity and URL origin are never
accepted from the caller. App Check follows the existing independent rollout flag.

| Callable | Additional request fields | Response fields beyond protocolVersion |
|---|---|---|
| `getWebMockLinkManagement` | none | `serverNowMs`, `tryouts`, `links` |
| `createWebMockLink` | `requestId` (22–80 base64url characters), `tryoutId` (1–80 safe ID characters), `contentFingerprint` (64 lowercase hex) | `serverNowMs`, `link`, `launchUrl` (one-time string or null on replay) |
| `revokeWebMockLink` | `linkId` (1–80 safe ID characters) | `serverNowMs`, `link` |

Owner summary: `linkId`, `tryoutId`, `contentFingerprint`, `status`,
`createdAtMs`, `expiresAtMs`. Status is active/claimed/expired/revoked/completed/
timeout. Only active/claimed may transition to revoked. Time-derived expiry is
persisted when touched; every read/replay/revoke rechecks it, without relying on
a cleanup job. Terminal states are permanent. No W2 endpoint creates claimed,
completed or timeout state; those are future-authority states tested by Admin
fixture setup. A revoked or expired link cannot be resumed by replaying create.

Tryout projection: `tryoutId`, `title` (1–120 chars), `contentFingerprint`,
`questionCount` (1–500), `durationSeconds` (60–14400). Responses contain no owner,
email, session ID, token digest, question, answer, explanation or score. Owner
management summaries are separate from the metadata-redacted public W1 landing
contract in `contracts/web-cbt`.

## Private model and atomicity

| Path | Data and authority |
|---|---|
| `web_mock_tryouts/{id}` | Admin-only bounded synthetic manifest; exact selected fingerprint validated during create |
| `web_mock_links/{random128bitId}` | Immutable ownerUid/tryoutId/contentFingerprint/sessionId/tokenHash/createdAt/expiresAt; mutable server-only status and optional revokedAt |
| `web_mock_owners/{uid}` | At most 20 tryout→latest-link slots; hourly issuance counter/window |
| `web_mock_owners/{uid}/create_requests/{requestDigest}` | Permanent request receipt with linkId and exact tryout/fingerprint |
| `web_mock_owners/{uid}/rate_limits/{read-or-mutation}` | Minute window start and call count |

`crypto.randomBytes(32)` creates a 256-bit capability, encoded as 43 base64url
characters. Only `SHA256("examcoach:web-link:v1:" + rawToken)` is stored. This is
a domain-separated one-way digest, not a keyed hash or password hash; the input
already has cryptographic entropy. Session ID and link ID each use independent
16-byte randomness. Firestore timestamps fix `expiresAt = createdAt + 43,200,000ms`.
The URL is fixed to `http://127.0.0.1:5173/mock-test#<opaque-token>` for local W2;
no UID, email, internal IDs or query parameters are included.

Creation transaction reads its request receipt, owner slots, trusted manifest
and prior link before writes. Same-key concurrent calls return one secret at
most; conflicting reuse is rejected. Different-key calls cannot replace an
unfinished link. Explicit revoke permits a new link/session/token. Revoke checks
ownership and state in the same transaction; unknown and foreign IDs receive
the same `not-found` error. No web record enters `users/{uid}/sessions`, so
existing mobile sync/recovery cannot mutate or import these intended sessions.

Per-UID development limits are 30 mutation calls/minute, 60 management calls/
minute and 6 successful new links/hour. Malformed/rejected authenticated calls
consume minute limits too; retries can receive `resource-exhausted`. Window
counters are transactional. Catalog and management return at most 20 entries;
the owner's 20 historical tryout slots are a deliberate local development cap.
No public validate endpoint or network/global abuse budget is implemented yet.
Retaining receipts/terminal records avoids replay resurrection; production
retention, slot reclamation, abuse budgets and entitlement policy require a
separate owner-reviewed design before activation.

All direct Firestore client reads/lists/writes to the private web roots are
denied, even for the owner or a client with an admin claim. Full published packs
are now denied too: their status never made answer-bearing documents safe for
public reads. Existing Flutter uses local content and authenticated callables,
so it has no dependency on that public rule. W3 must load immutable approved
packs and expose only a safe question projection. No content was published here.

## Local execution, no billing

Use Node 22 and Java 21. The native Firestore API used by this repository is
exercised against the Standard-compatible emulator; no live edition/database is
queried, provisioned or changed.

Server gates require all of `FUNCTIONS_EMULATOR=true`,
`EXAMCOACH_WEB_LINKS_ENABLED=true`, a `demo-*` project and a localhost/127.0.0.1
Firestore emulator host. Client bootstrap requires the explicit Web flag,
`useEmulators=true` and a demo project. Default/release configuration is closed.
W2 only accepts manifests labelled `emulator_fixture` plus `emulatorFixture=true`;
it rejects draft/validated/published substitutes. The seed is synthetic metadata,
not a published question pack or evidence of human review.

```bash
npm ci --prefix functions
# Copy the dummy overrides only when no local secret file exists.
test -f functions/.secret.local || cp functions/.secret.emulator.example functions/.secret.local
EXAMCOACH_WEB_LINKS_ENABLED=true EXAMCOACH_AI_EMULATOR_STUB=true \
EXAMCOACH_SUBSCRIPTION_EMULATOR_STUB=true \
npx --yes firebase-tools@15.8.0 emulators:start \
  --project demo-examcoach --only auth,firestore,functions
```

In a second terminal, seed the running local emulator:

```bash
GCLOUD_PROJECT=demo-examcoach FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
npm run seed:web-links --prefix functions
```

For Android emulator testing, create a local ignored `config/firebase.w2.json`
from the runtime example, set project `demo-examcoach`, API key `fake-api-key`,
sender ID `1234567890`, Android app ID `1:1234567890:android:abcdef123456`,
iOS placeholder app ID `1:1234567890:ios:abcdef123456`, Firebase enabled, emulator
use enabled, emulator host `10.0.2.2`, Web links enabled, and keep App Check,
Crashlytics and RevenueCat disabled. These are synthetic demo identifiers;
no Firebase project registration or secret is needed. Register/sign in through
local Auth, then open **Kerjakan di laptop**. Desktop link origin remains desktop
loopback, not Android's `10.0.2.2`. Real-device/HTTPS hosting is out of this stage.

```bash
flutter run --dart-define-from-file=config/firebase.w2.json
```

Automated emulator gate (also used by CI):

```bash
EXAMCOACH_WEB_LINKS_ENABLED=true EXAMCOACH_AI_EMULATOR_STUB=true \
EXAMCOACH_SUBSCRIPTION_EMULATOR_STUB=true \
npx --yes firebase-tools@15.8.0 emulators:exec \
  --project demo-examcoach --only auth,firestore,functions \
  'npm run test:rules --prefix functions && npm run test:callable --prefix functions'
```

## Acceptance and handoff

Tests cover auth/ownership, same/different-key races, exact server TTL, immutable
scope, lost-response replay, terminal revocation, expiry replacement, token shape
and uniqueness, hash-only storage, bounded rates, log canaries, direct CRUD/list
denials and denial of full published packs. Flutter tests cover strict response
parsing, safe error handling, copy consumption, pending-response races, sign-out,
refresh, close, double taps, default-disabled routing and 200% text management.

See [implementation log](../IMPLEMENTATION_LOG.md) for final counts, build and PR
results. W2 exit advances implementation to 2/5 (40%); W3 starts only on a fresh
branch from integrated develop. No production deployment, billing, domain,
iOS work, app release or main-branch change is authorized by this milestone.
