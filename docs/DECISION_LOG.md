# Decision Log

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
