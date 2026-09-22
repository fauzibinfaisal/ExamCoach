# ExamCoach — Web Mock Test Delivery Plan

Contract: [Web CBT PRD](../product/Web_Linked_Mock_Test_PRD.md).
Architecture: [DEC-014](../DECISION_LOG.md) and
[web platform audit](../architecture/Web_Platform_Architecture.md).
Security: [threat model](Web_Link_Security_Threat_Model.md).

## Milestones and boundaries

| Stage | Deliverable | Exit gate |
|---|---|---|
| W0 | Product contract, architecture questions and threat model | DEC-013/014 and threat model recorded |
| W1 | Separate web shell, sample profile, link landing, strict response contract, memory fake | Seven states, keyboard/reflow, build, default-closed behavior; Android/backend regression gates |
| W2 | Authenticated mobile create/revoke, private link records | Emulator auth/ownership, 12h server expiry, entropy/hash-only storage, rate limits, redacted telemetry |
| W3 | Secure browser claim and CBT workspace | Concurrent claim/cookie/CSRF tests, same-browser resume, published question projection, navigation/timer |
| W4 | Answer autosave/recovery, finalization and mobile result import | Shared Dart authority parity; exact evidence validation; idempotent submit and existing-history import |
| W5 | Security/browser/accessibility/performance acceptance | HTTPS cookie topology, Firefox/WebKit, screen reader, abuse/race tests, owner deployment readiness |

Progress denominator is five implementation milestones W1–W5; W0 is preparation.
W1–W2 completion is 2/5 = 40%, independently of the finished 12/12 mobile roadmap.

## W1 acceptance checklist

- [x] Architecture audit and DEC-014 precede implementation.
- [x] `apps/web` desktop shell and `/profile` sample context.
- [x] `/mock-test` validating/ready/claimed/expired/revoked/completed/invalid.
- [x] Strict versioned public response contract; denied responses have no metadata.
- [x] Explicit loopback-only fixture mode, no fake security implementation.
- [x] No questions, answer keys, actual claim, autosave, scoring or submit in W1.
- [x] Unit/component tests, browser keyboard/reflow, all status/terminal tests.
- [x] Formatter, type checker/linter, tests and default web build pass.
- [x] Flutter/Functions/emulator checks and Android debug budget still pass.
- [x] Structured commits and [PR #16](https://github.com/fauzibinfaisal/ExamCoach/pull/16) to develop; merge only after all hosted CI passes.

## W2 acceptance checklist

- [x] Authenticated mobile create/copy-once/refresh/revoke, default disabled.
- [x] Private owner/tryout/fingerprint/session binding and hash-only token storage.
- [x] Exact server-owned 12-hour lifetime and permanent terminal states.
- [x] Atomic same/different-request races, replay without token recovery.
- [x] Emulator ownership, payload, rate-limit, log-canary and persistence tests.
- [x] Direct full-pack reads closed; private Rules CRUD/list attack tests.
- [x] Synthetic manifest explicitly separated from human-approved publication.
- [x] Mobile async/lifecycle/privacy tests and unchanged web/backend regressions.

Local setup, data model, protocol, limits and evidence are in
[Web_Link_Management.md](Web_Link_Management.md). W2 does not implement browser
claim or start. Hosted CI remains mandatory before integration.

## Local execution

Use Node 22. Web commands are isolated under `apps/web`:

```bash
npm ci --prefix apps/web
npm run dev --prefix apps/web
npm run check --prefix apps/web
npm run test:e2e --prefix apps/web
npm run build --prefix apps/web
```

`dev` explicitly enables W1 fixtures on loopback. Open `/profile`, then the
preview link. Fixture selectors are named states, never security tokens. Default
`build` disables fixtures. The public `/mock-test` path safely refuses access
until the real gateway exists. The repository README documents browser installs.

Continue running the existing Flutter, Functions and Android commands in
`Release_Readiness.md`. All backend runs must use Firebase Emulator Suite with
`demo-examcoach`, never a live project; no billing is needed. Copy `functions/.secret.emulator.example` to the ignored
`functions/.secret.local` if no local secret file exists, and enable both
existing emulator stub flags for callable tests. This prevents Firebase CLI
Secret Manager lookups, even for a demo project. W1 adds no backend
endpoint and does not claim to test real links on the emulators.

## HTTP boundaries by milestone

- W2 implemented authenticated mobile callables: create/revoke/management;
  raw token returned once and never persisted by client or server.
- W3 same-origin `POST /api/web-cbt/validate` and `POST /api/web-cbt/claim` accept
  transient capability input; `GET /api/web-cbt/session` resumes by cookie.
- Public landing response schema: `contracts/web-cbt/link-status.v1.schema.json`.
  `validating` is a client loading state, not a server claim.
- W4 answer/final-submit endpoints use session authorization and revision/
  idempotency checks. Their payloads will be specified with implementation;
  W1 deliberately does not invent production request handlers.

W2 closed the public-published-content read rule and tested that full
answer-bearing packs are denied to every client. W3 must implement a safe
browser question projection. W4 must extend existing mobile recovery, which currently skips any
non-empty history, through a scoped deterministic import instead of overwriting
local data. Both are explicit work, not capabilities already implemented.

## Owner-only actions (later; none required to build W1)

- Select Firebase project/region, approve billing and budget alerts only when
  ready for hosted development; configure IAM/secrets and hosting/domain.
- Approve retention/deletion and monitoring policy, abuse limits and operational
  costs, including the proposed private Dart runtime.
- Provide named human review/publication of production question content.
- Decide full-profile web login/account UX beyond the link-scoped MVP.
- Require the new web CI check in GitHub branch protection once it exists.
- Complete physical-device/browser/screen-reader and release acceptance.

Do not deploy, enable billing, resume iOS, change `main`, or create `1.0.0` in W1.
After W2 integration, the next implementation session starts W3 on a new feature
branch from updated `develop`: browser claim/session recovery and CBT workspace.
Continue with demo emulators only.
