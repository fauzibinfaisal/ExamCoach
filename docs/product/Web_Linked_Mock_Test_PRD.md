# ExamCoach — Web-Linked Mock Test PRD

Status: Product behavior accepted; implementation not started

Owner: ExamCoach product owner

Last updated: 2026-09-18

## Purpose

Add a desktop-first browser mock-test experience that feels like a real
computer-based examination while keeping the mobile app as the trusted place
where the user creates access to the tryout.

This is a new **Web CBT Track** after the completed 12-step mobile repository
roadmap. It does not change the current mobile completion status or authorize a
production release.

## Product Model

1. The user has a primary ExamCoach profile.
2. In the authenticated mobile app, the user selects a tryout and chooses
   **Kerjakan di laptop**.
3. The backend creates an opaque browser link for that user and tryout.
4. The mobile app shows copy/share actions and may also show a QR code.
5. The user opens the link in a laptop browser.
6. The browser validates the link and shows the tryout identity, duration, and
   remaining link validity before start.
7. The user completes the tryout in a desktop-first computer-test interface.
8. Submission is recorded once, the result is computed by the deterministic
   learning rules, and access through that link becomes permanently inactive.
9. The mobile profile receives the completed result through the existing
   authenticated sync/recovery boundary.

## Link Contract

- A link is scoped to exactly one owner, one tryout definition, one content
  build/fingerprint, and one intended exam session.
- The link can be created only by an authenticated mobile user.
- The URL contains a cryptographically random opaque token, never a UID, email,
  answer, entitlement, or predictable database identifier.
- The raw token is returned only once to the mobile client. The backend stores
  only a one-way hash and bounded metadata.
- An unclaimed link expires exactly 12 hours after server-side creation. Client
  clock values are never trusted for expiry.
- The first valid browser claim binds access to one browser session. Reopening
  in the same browser may resume; another browser cannot take over silently.
- A tryout cannot start when the remaining link lifetime is shorter than the
  configured exam duration plus the server-defined submission grace window.
- The active browser session ends at the earliest of exam timeout, link expiry,
  owner revocation, or successful completion.
- Successful completion atomically marks the exam session complete and the link
  permanently unusable. Refresh, retry, or duplicate submit must not create a
  second result.
- Expired, completed, revoked, malformed, and already-bound links return a safe
  status page without revealing account or tryout data.
- The mobile user can revoke an unfinished link and create a replacement.

## Link Lifecycle

```text
created/active
  ├── first valid browser claim → claimed/in_progress
  │     ├── submit/timeout → completed (terminal)
  │     ├── owner revoke → revoked (terminal)
  │     └── 12-hour deadline → expired (terminal)
  ├── owner revoke → revoked (terminal)
  └── 12-hour deadline → expired (terminal)
```

Terminal states are immutable. A replacement always receives a new link and
token; an old token is never reactivated.

## Primary Web Experience

### Link landing

- ExamCoach branding and primary profile context without exposing personal data.
- Tryout title, subtests, total questions, duration, and rules.
- Link-validity countdown using server time.
- Clear states for ready, already claimed elsewhere, expired, revoked, and
  completed.
- Start confirmation and device/browser compatibility notice.

### Computer-test workspace

- Desktop-first layout that remains usable on supported tablets.
- Persistent exam timer and link/session status.
- Current question, answer options, and previous/next controls.
- Question navigator with not-seen, unanswered, answered, doubtful, and skipped
  states.
- Mark-as-doubtful control without changing the chosen answer.
- Keyboard navigation with visible focus and screen-reader semantics.
- Autosave after every meaningful action, with pending/saved/failure feedback.
- Safe refresh/reconnect recovery without resetting the timer or duplicating an
  answer.
- Final review and explicit submit confirmation.

### Completion

- Idempotent final submission.
- Deterministic score, review access policy, weaknesses, and recommendation.
- Clear confirmation that the access link is no longer active.
- Result becomes available to the owner profile/mobile app after sync.

## Security and Privacy Requirements

- HTTPS only outside local emulators.
- At least 128 bits of effective token entropy; 256 bits is preferred.
- Store only a keyed/cryptographic token hash, never the raw token.
- Never log tokens or include them in analytics, crash reports, page titles,
  referrers, screenshots, or third-party URLs.
- Use an HttpOnly, Secure, SameSite browser-session cookie after claim and
  remove the token from visible browser history as soon as practical.
- Rate-limit create, validate, claim, autosave, and submit operations.
- All ownership, expiry, content fingerprint, attempt state, and completion
  checks are server-owned and transactional.
- App Check is additive for mobile link creation; it does not replace Firebase
  Authentication, server authorization, or link-token validation.
- A capability link grants only the named tryout session, not general profile,
  account, subscription, or historical-data access.

## Deterministic Learning Boundary

- The web client must not become authoritative for correctness, score,
  weakness, recommendation, quota, or entitlement.
- Question and content fingerprints must match the server-approved published
  pack.
- Final correctness and score are recomputed or verified at the trusted
  boundary using the same versioned rules as the mobile learning engine.
- AI may explain a completed deterministic result but cannot decide it.

## Conceptual Server Record

The exact datastore schema remains an architecture decision, but the trusted
record needs at least:

```text
link_id
owner_uid
tryout_id
content_fingerprint
session_id
token_hash
status
created_at
expires_at
claimed_at
browser_session_hash
completed_at
revoked_at
revision
```

Server timestamps are required. Raw tokens, email addresses, and answer text do
not belong in the record.

## Delivery Track

| Milestone | Outcome | Status |
|---|---|---|
| W0 | Product contract, threat model, and open decisions | In progress |
| W1 | Web stack/monorepo decision and desktop shell | Not started |
| W2 | Authenticated mobile link creation and revocation | Not started |
| W3 | Secure browser claim and computer-test workspace | Not started |
| W4 | Autosave, reconnect recovery, submit, result sync | Not started |
| W5 | Security, accessibility, browser, performance, and release gates | Not started |

## Acceptance Criteria

- [ ] An authenticated mobile user can create a link for one tryout.
- [ ] The displayed expiry is based on the backend timestamp plus 12 hours.
- [ ] The link opens a laptop-ready landing page without requiring mobile UI.
- [ ] A second browser cannot silently take over an already claimed attempt.
- [ ] Refreshing the claimed browser restores the exact current state.
- [ ] Autosave/retry cannot create duplicate answers or extend the timer.
- [ ] Expired, revoked, completed, and malformed links cannot access questions.
- [ ] Final submit is idempotent and immediately deactivates the link.
- [ ] Mobile and web show the same deterministic result for the same evidence.
- [ ] Raw link tokens and personal/answer data never enter logs or analytics.
- [ ] Keyboard-only, screen-reader, narrow desktop, and supported browser tests
  pass.
- [ ] Emulator and automated security tests pass before any real deployment.

## Open Decisions for the New Session

The implementation session must audit and record these decisions before coding:

1. Flutter Web in the current package versus a separate web frontend/monorepo.
2. How deterministic scoring/content contracts are shared without duplicating
   authority.
3. Browser persistence and secure session-cookie architecture.
4. Whether the full web profile requires normal login in W1 or follows after
   the link-scoped MVP.
5. Supported browsers/tablets and minimum desktop viewport.
6. Hosting, domain, Firebase billing timing, observability, and retention.

Real hosted link creation requires a trusted online backend. The complete flow
can be developed against Firebase Emulator Suite before billing is enabled;
real Cloud Functions deployment remains an owner-controlled later step.
