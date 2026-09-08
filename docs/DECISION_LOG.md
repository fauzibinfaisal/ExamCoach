# Decision Log

## DEC-010 — Single-Owner Local Binding and Empty-Device Firebase Recovery

Date: 2026-09-08

Status:
- Accepted

Context:

The Step 8 outbox can safely upload retries, but authenticated remote ownership
and inbound recovery introduce a different risk: a sign-in or remote snapshot
could relabel, merge, or overwrite deterministic local learning evidence. The
repository also has no owner-supplied Firebase project, so remote initialization
must not make local development unusable.

Decision:

Make Firebase an explicit runtime capability that fails closed to local-only
mode. At first successful sign-in, transactionally bind the SQLite database to
one Firebase UID and claim all `local_user` session, analytics, and matching
outbox ownership. Retain that binding after sign-out and refuse another UID.
Route all remote mutations through authenticated callable Functions; deny direct
Firestore learning writes. Store stable operation IDs, canonical payload hashes,
and per-user revisions remotely. Import an owned remote snapshot only when the
local database has no sessions, validate it against installed content, and
recompute correctness/score locally.

Reason:

- Local offline learning remains available without a Firebase project or
  network.
- Permanent single-owner binding prevents one account from inheriting another
  user's local evidence.
- Transactional owner claim avoids partially relabeled sessions/outbox data.
- Callable authorization and deny-by-default writes centralize trust and state
  transition checks.
- Empty-device-only import avoids inventing an unsafe two-way merge policy.
- Local recomputation preserves the deterministic engine as source of truth and
  does not trust uploaded correctness or score.

Alternatives Considered:

- Require Firebase at app startup: rejected because it breaks offline-first
  learning and local development.
- Direct client writes guarded only by Rules: rejected because lifecycle,
  idempotency, and revision invariants need server transactions.
- Replace local state with remote state after every login: rejected because it
  can destroy newer or unsynced evidence.
- Merge two non-empty devices by timestamp: rejected because session lifecycle,
  edited answers, content versions, and insight recomputation need a reviewed
  domain policy rather than generic last-write-wins.
- Allow immediate account switching on one database: rejected because safe
  export/reset consent and deletion behavior are not implemented.

Impact:

- SQLite schema v7 adds singleton `account_binding` metadata.
- The Firebase gateway is registered only with complete Dart-define
  configuration; otherwise Account UI reports local mode.
- Sign-out preserves local data and binding.
- A clean second device with matching content can recover up to 200 sessions and
  5,000 answers; a non-empty device keeps its local state and uploads it.
- General reconciliation, explicit reset/account switch, App Check,
  observability, and real-project deployment remain future/owner work.

Related Documents:

- `docs/engineering/Firebase_Integration.md`
- `docs/engineering/Sync_Architecture.md`
- `docs/engineering/Local_Persistence_Design.md`
- `docs/architecture/Backend_Service_Architecture.md`

## DEC-009 — Digest-Bound Human Review and Immutable Content Promotion

Date: 2026-09-06

Status:
- Accepted

Context:

External AI can generate structurally valid question drafts, but machine checks
cannot establish factual correctness, a single defensible answer, editorial
quality, calibrated difficulty, originality, or the right to publish. Updating
reviewed content in place would also change the meaning of historical sessions
that reference stable pack and question IDs.

Decision:

Keep generated imports at `draft`. Before human review, block normalized exact
prompt matches and three-token Jaccard similarity at or above `0.82` within the
candidate and against the bank. Require a named human to complete all eleven
review checks for the exact question scope and record UTC time, notes, and
provenance. Bind that evidence to a canonical SHA-256 fingerprint of all
immutable pack/question meaning. Promote only through separate forward-only
`draft → validated → published` actions, writing and retaining a new artifact at
each state. Corrections require new content versions and new IDs.

Reason:

- Human accountability remains explicit and cannot be inferred from successful
  parsing or AI generation.
- A content fingerprint makes review evidence invalid after any meaningful
  content, answer, taxonomy, provenance, or selection change.
- Separate validation and publication preserve a clear editorial control point.
- Retained immutable artifacts preserve auditability and historical session
  meaning.
- A deterministic similarity gate catches obvious overlap consistently while
  leaving semantic originality and rights assessment to the reviewer.

Alternatives Considered:

- Auto-approve structurally valid AI output: rejected because correctness and
  publication rights cannot be proven mechanically.
- Store a mutable status on one asset file: rejected because content and review
  history could be silently rewritten.
- Let the same ID represent corrected wording or answers: rejected because old
  session evidence would change meaning.
- Treat the similarity threshold as proof of originality: rejected because
  paraphrases and conceptual copying require human judgment.

Impact:

- Raw external imports remain schema-v1 drafts; reviewed lifecycle artifacts use
  schema v2.
- SQLite schema v6 stores review/provenance/fingerprint and publication evidence
  and permits only matching forward lifecycle advancement.
- Content operations require a reviewer-operated sidecar followed by an explicit
  publisher action.
- The repository currently has no human-approved or published question pack;
  the built-in prototype remains development-only draft content.

Related Documents:

- `docs/operations/Human_Question_Review_Workflow.md`
- `docs/operations/AI_Question_Bank_Workflow.md`
- `docs/operations/Content_Operations_SOP.md`
- `docs/architecture/CMS_System_Architecture.md`
- `docs/engineering/Local_Persistence_Design.md`

## DEC-008 — Pre-1.0 Application Versioning

Date: 2026-09-06

Status:
- Accepted

Context:

The generated Flutter scaffold used `1.0.0+1`, but ExamCoach is still in active
development, has no production release, and is only eight milestones into the
twelve-step delivery plan.

Decision:

Use `0.MINOR.PATCH+BUILD` until the first owner-approved production release.
Increment `MINOR` for roadmap capabilities, `PATCH` for compatible fixes, and
the integer `BUILD` for every distributable mobile artifact. Set the Step 8
build to `0.8.0+8`. Keep SQLite schema versions independent from application
versions. Reserve `1.0.0` and the `v1.0.0` Git tag for the first stable
production release.

Reason:

- Semantic Versioning defines major version zero for initial development.
- A strictly numeric three-part build name is portable across Flutter's Android
  and iOS release tooling.
- Monotonic build numbers give stores and testers an unambiguous artifact order.
- Separating application and database versions prevents unsafe migration
  assumptions.

Alternatives Considered:

- Keep `1.0.0+1`: rejected because it falsely signals a stable public release.
- Use only a date or Git SHA: rejected because mobile stores still require
  platform version/build metadata.
- Make the app version equal the database schema version: rejected because UI,
  domain, content, and build changes do not map one-to-one to schema migrations.

Impact:

- Current Android and iOS debug artifacts identify as version `0.8.0`, build
  `8`.
- The next compatible Step 8 fix starts at `0.8.1+9`; the next milestone starts
  at `0.9.0` with a build number greater than eight.
- Release tags are created only from approved `main` release commits.

Related Documents:

- `docs/engineering/Release_Versioning.md`
- `docs/engineering/Git_Workflow.md`

## DEC-007 — Idempotent Batched Outbox Delivery and Explicit Supersession

Date: 2026-09-06

Status:
- Accepted

Context:

ExamCoach already commits learning and analytics mutations into a transactional
SQLite outbox. Delivering those operations over an unreliable network requires
retry scheduling, acknowledgement, and conflict semantics that cannot corrupt or
block the local deterministic learning loop.

Decision:

Upload ready operations in stable, bounded batches through a provider-neutral
gateway. Use the stable operation ID as the remote idempotency key and require an
explicit accepted, duplicate, superseded, retryable-failure, or rejected result
per operation. Retry transient or missing acknowledgements with capped
exponential backoff; move permanent failures or the fifth failed attempt to a
durable dead letter. Treat `superseded` as completed upload delivery without
mutating local learning evidence. Prune only acknowledged delivery rows and
synced analytics sources after seven days.

Reason:

- Local progression remains immediate and offline-first.
- Explicit per-operation outcomes make partial and uncertain batch responses
  recoverable.
- A replay that reaches the server before a response is lost becomes a harmless
  duplicate.
- Durable dead letters prevent poison operations from blocking the ready queue.
- Keeping inbound reconciliation separate prevents an upload transport layer
  from silently changing official local learning results.

Alternatives Considered:

- Best-effort direct writes: rejected because an app/network interruption can
  lose data.
- Mark a full batch synced after any successful response: rejected because
  partial acknowledgement would silently discard operations.
- Let the worker resolve supersession by overwriting local learning rows:
  rejected because conflict ownership requires authenticated cross-device
  context and domain-specific reconciliation.
- Retry forever: rejected because permanent failures would waste resources and
  hide operational defects.

Impact:

- SQLite schema v5 stores scheduling, acknowledgement, revision, and
  dead-letter metadata.
- A production remote must implement operation-ID deduplication, ordered batch
  results, user/entity authorization, and revision/state-transition validation.
- Runtime registration remains deferred until the authenticated Firebase
  boundary exists.

Related Documents:

- `docs/engineering/Sync_Architecture.md`
- `docs/engineering/Local_Persistence_Design.md`
- `docs/architecture/Backend_Service_Architecture.md`

## DEC-006 — Review-Gated, Resumable Session Lifecycle

Date: 2026-09-06

Status:
- Accepted

Context:

The sequential prototype scored immediately after the sixth answer and could
only recover the next unanswered question. The product now needs explicit skip,
answer revision, cancellation, abandoned-session handling, and post-result
review while preserving offline durability and deterministic scoring.

Decision:

Model a skip as a durable nullable answer-domain state, require every question
to have an answer-or-skip record before entering a pre-submit review state, and
calculate the result only after explicit completion. Persist edits with a sticky
changed-answer flag and replaceable idempotent outbox payload. Persist cancelled
and expired sessions as terminal records but exclude their answers from learning
history. Expire active sessions after a provisional 24 hours of inactivity at
recovery. Route explanation visibility through `QuestionReviewAccessPolicy`.

Reason:

- Explicit completion prevents an accidental last tap from finalizing a tryout.
- Durable skip/edit state makes interruption and recovery predictable.
- Retaining terminal sessions supports future audit and cross-device sync while
  protecting weakness/recommendation calculations from partial data.
- A policy boundary supports future entitlements without coupling monetization
  to scoring, persistence, or result rendering.

Alternatives Considered:

- Score automatically after the final response: rejected because it removes the
  opportunity to inspect skips and revise mistakes before submission.
- Delete cancelled or expired sessions: rejected because it loses audit and
  future synchronization context.
- Count partial responses in history: rejected because unfinished sessions can
  distort weakness and recommendation evidence.
- Implement subscription tiers now: rejected because pricing and trusted remote
  entitlement validation are not yet implemented.

Impact:

- SQLite schema v4 stores explicit skipped state.
- Session orchestration now has `idle`, `answering`, `reviewing`, and `result`
  states.
- A 24-hour expiry is an explicitly provisional local product default.
- Sync must preserve latest-write answer/progress semantics and terminal session
  outcomes.
- The development build exposes all draft explanations; production entitlement
  policy remains future work.

Related Documents:

- `docs/product/PRD.md`
- `docs/engineering/Analytics_Event_Map.md`
- `docs/engineering/Local_Persistence_Design.md`
- `docs/engineering/Session_Controls_and_Review.md`

## DEC-001 — Local Deterministic Vertical Slice First

Date: 2026-09-05

Status:
- Accepted

Context:

The workspace contains comprehensive requirements but no application, backend, or Flutter scaffolding. The documented delivery rule prioritizes a working Question → Answer → Score → Weakness → Recommendation → Drill loop before backend, AI, or architecture refinement.

Decision:

Build the first learning loop entirely from a development-only in-app mock question pack. Keep it visibly marked as `draft` until human validation. Place scoring, weakness analysis, recommendation, and drill selection in pure Dart modules, with Flutter responsible only for workflow and presentation.

Reason:

This produces a testable offline-first product slice immediately, respects the AI boundary, and avoids coupling the initial domain to Firebase or any one exam.

Alternatives Considered:

- Integrate Firebase first: rejected because it delays the core learning loop and is not required for local scoring and insight.
- Ask an AI provider to generate insights: rejected because deterministic structured insight is the required source of truth.
- Build a broad reusable framework first: rejected as premature for a documentation-only repository.

Impact:

- The first milestone will run without network access.
- Repository contracts can later gain local/remote implementations without changing learning-engine rules.
- Mock content must be clearly identified and retain required taxonomy/provenance metadata.

Related Documents:

- `docs/product/PRD.md`
- `docs/engineering/Learning_Intelligence_Specification.md`
- `docs/architecture/Flutter_Modular_Architecture.md`
- `docs/architecture/Technical_Design_Document.md`

## DEC-002 — Provisional Learning Engine V1 Defaults

Date: 2026-09-05

Status:
- Accepted

Context:

The learning intelligence specification requires configurable weights, a safeguard against declaring weakness from one question, explainable recommendations, and an initial 70/20/10 drill composition. It intentionally does not prescribe calibrated numerical weakness weights or thresholds because those require experimental validation.

Decision:

Use the following explicitly versioned prototype defaults:

- `weakness_v1`: 65% accuracy deficit, 20% time-over-target penalty, and 15% difficulty-weighted miss penalty.
- Require at least two samples before classifying a topic as weak; use five samples for full confidence.
- Classify weakness scores at or above 0.55 as weak and below 0.30 as strong; the middle band remains medium.
- Treat a weakness-score decrease of at least 0.05 as improving and an increase of at least 0.05 as declining.
- `adaptive_drill_v1`: apply configurable 70% weak / 20% medium / 10% strong targets using largest-remainder integer allocation, prioritizing unseen questions.
- Rank recommendation targets by weakness score multiplied by confidence, and always provide a structured reason code.

Reason:

These defaults are simple, deterministic, testable, explainable, and configuration-driven. They allow the required learning loop to function without pretending the model has already been statistically calibrated.

Alternatives Considered:

- Accuracy-only weakness: rejected because it ignores the documented speed and difficulty signals.
- Classify a topic after one answer: rejected because it violates the explicit evidence safeguard.
- Random drill selection: rejected because it harms reproducibility and testability.
- Hard-code exact question counts per tier: rejected because the drill session size will vary.

Impact:

- Product and analytics teams must treat current outputs as prototype insights, not validated predictions.
- Future calibration can replace configuration values without changing UI or orchestration contracts.
- Recency, cross-session consistency, spaced repetition, fatigue, and richer exposure modeling remain future engine versions.

Related Documents:

- `docs/product/PRD.md`
- `docs/engineering/Learning_Intelligence_Specification.md`
- `docs/architecture/Technical_Design_Document.md`

## DEC-003 — SQLite and Transactional Outbox for Mobile Persistence

Date: 2026-09-05

Status:
- Accepted

Context:

The first learning loop held all state in memory. The offline-first requirements demand durable question packs, active sessions, answers, local results, recommendations, analytics, migration support, and idempotent synchronization on Android and iOS.

Decision:

Use SQLite through `sqflite` as the initial mobile persistence engine. Keep SQL schema and migrations explicit in `ExamCoachDatabase`, inject the database factory for tests, and use `sqflite_common_ffi` only as a development dependency. Store remote-bound local mutations in a transactional outbox with stable operation IDs.

Reason:

- SQLite provides transactions, constraints, indexes, and explicit migrations for the relational learning data in the ERD.
- `sqflite` directly supports the two target platforms and remains actively maintained.
- Factory injection permits real SQLite tests without an emulator.
- Explicit SQL avoids adding code-generation and ORM complexity before query requirements stabilize.
- A transactional outbox prevents a successful local learning action from depending on network availability.

Alternatives Considered:

- Shared preferences/key-value storage: rejected because it is unsuitable for relational sessions, answer history, migrations, and queued operations.
- Drift: viable and type-safe, but deferred because generated schema code and additional build tooling are not yet justified by the small schema/query surface.
- Firebase-only persistence: rejected because the core learning loop must work and commit progress without a network connection.
- Direct best-effort remote writes: rejected because failures could lose events or couple progression to connectivity.

Impact:

- Local writes are authoritative for the current device and survive process/database restarts.
- Backend integration can consume `SyncOutboxRepository` without changing scoring or UI workflows.
- Future schema changes require an explicit migration and migration test.
- A retention policy and background sync worker are still required before production scale.

Related Documents:

- `docs/engineering/Database_ERD.md`
- `docs/engineering/Analytics_Event_Map.md`
- `docs/engineering/Local_Persistence_Design.md`
- `docs/architecture/Flutter_Modular_Architecture.md`
- `docs/architecture/Technical_Design_Document.md`

## DEC-004 — Git Flow Branching and Release Model

Date: 2026-09-06

Status:
- Accepted

Context:

The project has been published to GitHub and needs a predictable separation
between active development, stable releases, release preparation, and urgent
production fixes.

Decision:

Use `main` as the production/release branch and `develop` as the active
integration branch. Normal work starts from `develop` in `feature/*` or
`bugfix/*`; releases use `release/*`; urgent released-code fixes use `hotfix/*`.
Release merges into `main` receive `vX.Y.Z` semantic-version tags, and release or
hotfix changes are always merged back into `develop`.

Reason:

- Stable release history remains separate from incomplete integration work.
- Release stabilization and urgent fixes have explicit, auditable paths.
- A consistent branch vocabulary reduces ambiguous pull request targets.
- Back-merging prevents released fixes from disappearing from future versions.

Alternatives Considered:

- GitHub Flow with only `main`: simpler, but rejected because the requested
  delivery model requires a persistent `develop` integration branch.
- Direct development on `develop`: permitted only for initial administration;
  rejected for normal implementation because short-lived branches improve
  review, rollback, and ownership.
- Long-lived branches per environment: rejected until actual deployment
  environments require them.

Impact:

- GitHub's default branch becomes `develop` for normal pull requests.
- `main` accepts only release and hotfix changes.
- Contributors must follow the validation and merge rules in
  `docs/engineering/Git_Workflow.md`.

Related Documents:

- `CONTRIBUTING.md`
- `docs/engineering/Git_Workflow.md`
- `docs/PROJECT_STATUS.md`

## DEC-005 — Provider-Neutral AI Draft Ingestion

Date: 2026-09-06

Status:
- Accepted

Context:

The owner needs to generate new question drafts with external AI tools and add
them to the local ExamCoach question bank. The content SOP requires provenance,
taxonomy, auditability, and human validation, while the architecture forbids AI
from becoming the source of truth for scoring or learning decisions.

Decision:

Accept external AI output only through the versioned
`ai_question_pack_v1` JSON contract. Validate it deterministically with a local
CLI, store accepted files in a manifest-backed Flutter asset bank, and import
unseen immutable packs transactionally into SQLite. All packs accepted by this
pipeline must remain `draft` with no reviewer claim.

Reason:

- The workflow supports any AI provider or local model without runtime vendor
  coupling, credentials, or network requirements.
- Deterministic validation prevents malformed content from silently entering the
  local database.
- Immutable IDs and versions preserve completed-session answer history.
- Explicit generator, author, provenance, and timestamp metadata support future
  audits.
- Enforced draft status preserves the human content quality gate.

Alternatives Considered:

- Call one AI provider directly from the mobile app: rejected because it adds
  credential, availability, cost, safety, and vendor-lock-in risks.
- Paste questions directly into Dart source: rejected because it is difficult to
  validate, audit, version, and automate.
- Let AI mark its own output validated: rejected because machine self-review
  cannot satisfy the documented editorial gate.
- Overwrite a pack in place: rejected because changed answers could corrupt the
  meaning of historical attempts.

Impact:

- Owners can generate and test new draft packs through documented CLI commands.
- SQLite schema v3 retains pack generator and question authorship metadata.
- A new app build is required to distribute newly imported asset packs.
- Semantic review, similarity detection, reviewer signoff, and production
  promotion tooling remain future work.

Related Documents:

- `content/question_pack.schema.json`
- `content/ai_question_prompt.md`
- `docs/operations/Content_Operations_SOP.md`
- `docs/operations/AI_Question_Bank_Workflow.md`
- `docs/engineering/Local_Persistence_Design.md`
