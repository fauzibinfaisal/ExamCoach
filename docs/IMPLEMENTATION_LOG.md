# Implementation Log

## 2026-09-06 — Connectivity-Aware Sync Worker and Pre-1.0 Versioning

### Objective

Turn the durable SQLite outbox into a safe, bounded delivery engine that can
survive offline use, uncertain remote responses, retries, and conflicts without
changing local deterministic learning behavior.

### Implemented

- Added a provider-neutral `SyncRemoteGateway` with accepted, duplicate,
  superseded, retryable-failure, and permanent-rejection outcomes.
- Added a `ConnectivityPlusMonitor` and startup/reconnect coordinator while
  treating network transport as a trigger rather than proof of internet access.
- Added a single-flight worker with stable queue ordering, batches of 25, a
  maximum of ten batches per run, and structured run summaries.
- Added exponential retry from five seconds to fifteen minutes, a five-attempt
  cap, missing-acknowledgement recovery, and durable dead-letter quarantine.
- Added explicit acknowledgement and optional remote-revision metadata.
- Defined supersession as a completed upload that never rewrites local answers,
  score, weakness, recommendation, or insight.
- Added seven-day bounded pruning for acknowledged outbox rows and their synced
  analytics sources while retaining learning data, pending work, and dead
  letters.
- Migrated SQLite from schema v4 to v5 and backfilled legacy synced operations.
- Added real-SQLite/fake-remote coverage for offline reconnect, batching,
  idempotent duplicates, supersession, transport ambiguity, rejection, retry
  exhaustion, retention, and v1/v4→v5 migrations.
- Added `connectivity_plus`, explicitly set the iOS minimum deployment target to
  13.0, and validated the installed Android/iOS toolchain requirements.
- Adopted `0.MINOR.PATCH+BUILD` for unreleased development and changed the app
  version from `1.0.0+1` to `0.8.0+8`.
- Added sync architecture and release-versioning guides and reconciled the
  project handoff documentation.

### Files Changed

- `lib/services/sync/application/sync_worker.dart`
- `lib/services/sync/application/sync_coordinator.dart`
- `lib/services/sync/data/connectivity_plus_monitor.dart`
- `lib/services/sync/domain/connectivity_monitor.dart`
- `lib/services/sync/domain/sync_outbox_item.dart`
- `lib/services/sync/domain/sync_outbox_repository.dart`
- `lib/services/sync/domain/sync_remote_gateway.dart`
- `lib/services/sync/domain/sync_retry_policy.dart`
- `lib/services/sync/domain/sync_run_summary.dart`
- `lib/features/learning/data/local_learning_persistence_repository.dart`
- `lib/services/database/exam_coach_database.dart`
- `test/services/sync/sync_worker_integration_test.dart`
- `test/services/sync/sync_coordinator_test.dart`
- `test/persistence/local_persistence_integration_test.dart`
- `pubspec.yaml`
- `pubspec.lock`
- `ios/Podfile`
- `ios/Podfile.lock`
- `README.md`
- `CONTRIBUTING.md`
- `docs/README.md`
- `docs/PROJECT_STATUS.md`
- `docs/IMPLEMENTATION_LOG.md`
- `docs/DECISION_LOG.md`
- `docs/architecture/Backend_Service_Architecture.md`
- `docs/engineering/Analytics_Event_Map.md`
- `docs/engineering/Database_ERD.md`
- `docs/engineering/Git_Workflow.md`
- `docs/engineering/Local_Persistence_Design.md`
- `docs/engineering/Release_Versioning.md`
- `docs/engineering/Sync_Architecture.md`

### Technical Decisions

- Keep local commits authoritative and let the upload worker change delivery
  metadata only.
- Use stable operation IDs for remote idempotency and explicit per-operation
  acknowledgement for uncertain batch delivery.
- Treat remote supersession as successful delivery, leaving inbound
  cross-device reconciliation to the authenticated remote milestone.
- Keep the production gateway unwired until Firebase Auth, ownership, security
  rules, and server revision enforcement exist in Step 10.
- Separate semantic app versioning from SQLite schema versioning.

### Validation

- `dart format lib test` — PASS.
- `flutter analyze` — PASS; no issues found.
- Focused SQLite/sync suite — PASS; 17 tests passed.
- `flutter test` — PASS; 37 tests passed.
- `flutter build apk --debug` — PASS; version `0.8.0`, build `8`, 155 MB.
- Android debug APK SHA-256 —
  `b439675d71a60b1b02f1d3735540b50562da89f9cce0590acc4087f2afb0b417`.
- `flutter build ios --debug --no-codesign` — PASS; version `0.8.0`, build
  `8`.
- GitHub pull request #5 — MERGED into `develop`; `main` unchanged.

### Result

PASS

### Next Step

- Implement Step 9 human review evidence, duplicate/similarity checks, and
  immutable publication tooling for the question bank.
- Implement and register the authenticated production sync gateway only with
  the Step 10 Firebase/Auth boundary.

## 2026-09-06 — Resumable Session Controls and Answer Review

### Objective

Let users skip and revise responses, explicitly review before scoring, safely
cancel or recover sessions, and inspect answers after a result without weakening
the deterministic offline learning loop.

### Implemented

- Added explicit skipped responses and sticky answer-change tracking with
  accumulated time across edits.
- Added previous-question navigation and saved-answer preselection.
- Added a pre-submit review screen with answered/skipped counts and editing of
  any response before an explicit finish action.
- Added confirmation-based session cancellation from overview, active question,
  and review flows; partial cancelled answers do not enter learning history.
- Added bootstrap expiry for active sessions inactive for more than 24 hours;
  expired partial answers remain excluded from learning insight.
- Added direct recovery to the exact saved question or pre-submit review state.
- Added post-result cards for user answer, correct answer, correctness status,
  and explanation.
- Added an entitlement-ready `QuestionReviewAccessPolicy`; the development
  policy currently permits all local draft explanations.
- Migrated SQLite from schema v3 to v4 with explicit `is_skipped` storage.
- Added replaceable outbox operations for edited answers and session progress,
  plus terminal cancellation and expiry operations.
- Added centralized skip, change, cancellation, expiry, and question-review
  analytics.
- Expanded Cubit, SQLite integration, migration, and widget tests to cover the
  new lifecycle end to end.
- Added the session-control design and manual testing guide.

### Files Changed

- `lib/analytics/analytics_events.dart`
- `lib/app/router.dart`
- `lib/features/exam/domain/models/answer_record.dart`
- `lib/features/home/presentation/home_page.dart`
- `lib/features/learning/application/learning_flow_cubit.dart`
- `lib/features/learning/application/learning_flow_state.dart`
- `lib/features/learning/data/local_learning_persistence_repository.dart`
- `lib/features/learning/data/transient_learning_persistence_repository.dart`
- `lib/features/learning/domain/repositories/learning_persistence_repository.dart`
- `lib/features/practice/presentation/question_page.dart`
- `lib/features/practice/presentation/session_cancel_dialog.dart`
- `lib/features/practice/presentation/session_review_page.dart`
- `lib/features/practice/presentation/tryout_overview_page.dart`
- `lib/features/result/domain/question_review_access_policy.dart`
- `lib/features/result/presentation/answer_review_page.dart`
- `lib/features/result/presentation/result_page.dart`
- `lib/learning_engine/models/score_result.dart`
- `lib/services/database/exam_coach_database.dart`
- `test/features/learning/learning_flow_cubit_test.dart`
- `test/persistence/local_persistence_integration_test.dart`
- `test/widget_test.dart`
- `README.md`
- `docs/README.md`
- `docs/PROJECT_STATUS.md`
- `docs/IMPLEMENTATION_LOG.md`
- `docs/DECISION_LOG.md`
- `docs/engineering/Analytics_Event_Map.md`
- `docs/engineering/Database_ERD.md`
- `docs/engineering/Local_Persistence_Design.md`
- `docs/engineering/Session_Controls_and_Review.md`

### Technical Decisions

- Treat answer and skip as equally durable response states, while scoring skips
  as incorrect only after explicit session completion.
- Require a pre-submit review transition instead of auto-scoring after the final
  response.
- Keep cancelled and expired sessions for audit/sync but exclude them from all
  completed learning history.
- Use a provisional 24-hour inactivity window until remote product
  configuration exists.
- Put explanation visibility behind a synchronous policy boundary without
  implementing pricing or subscription rules prematurely.

### Validation

- `dart format lib test` — PASS.
- `flutter analyze` — PASS; no issues found.
- `flutter test` — PASS; 27 tests passed.
- SQLite real-file integration suite — PASS; v1→v4 migration, response edits,
  review recovery, cancellation, expiry, history isolation, and outbox verified.
- Widget journey — PASS; cancel confirmation and
  skip→edit→review→result→explanation→drill verified.
- `flutter build apk --debug` — PASS.
- `flutter build ios --debug --no-codesign` — PASS.
- GitHub pull request #3 — MERGED into `develop`; `main` unchanged.

### Result

PASS

### Next Step

- Implement the connectivity-aware sync worker, retry/dead-letter policy,
  remote acknowledgement, and fake-remote integration tests against the
  existing outbox contract.

## 2026-09-06 — External-AI Question Bank Ingestion

### Objective

Allow the owner to generate question drafts with any external AI, validate them
deterministically, and add them to the offline question bank without giving AI
runtime authority over answers or learning decisions.

### Implemented

- Added the versioned `ai_question_pack_v1` JSON contract and JSON Schema.
- Added a reusable Indonesian AI prompt and a valid six-question example pack.
- Added a pure Dart codec and semantic validator for pack metadata, options,
  answers, taxonomy, timing, provenance, authorship, versions, and tryout IDs.
- Enforced AI-generated `draft` status and null reviewer claims.
- Added a CLI with `validate`, `import`, `import --activate`, and `list` commands.
- Made imports non-destructive by rejecting duplicate pack/question IDs and
  existing destination files.
- Added a safe asset manifest and bootstrap loader independent of any AI vendor.
- Extended the local repository to import unseen packs transactionally, retain
  all questions for historical sessions, and select the active tryout through
  stable IDs.
- Migrated SQLite from schema v2 to v3 with pack generator, author, reviewer,
  and tryout-selection audit metadata.
- Added validator, manifest safety, asset-loader, migration, active-pack, and
  idempotent re-import tests.
- Added the end-user generation/import workflow and updated persistence/content
  documentation.

### Files Changed

- `assets/question_bank/manifest.json`
- `content/ai_question_prompt.md`
- `content/question_pack.schema.json`
- `content/examples/question_pack.example.json`
- `tool/question_bank.dart`
- `lib/bootstrap/bootstrap.dart`
- `lib/features/exam/data/bundled_question_bank_loader.dart`
- `lib/features/exam/data/local_question_repository.dart`
- `lib/features/exam/data/question_bank_manifest.dart`
- `lib/features/exam/data/question_pack_codec.dart`
- `lib/features/exam/data/mock_question_repository.dart`
- `lib/features/exam/domain/models/question.dart`
- `lib/features/exam/domain/models/question_pack.dart`
- `lib/services/database/exam_coach_database.dart`
- `test/features/exam/question_pack_codec_test.dart`
- `test/persistence/local_persistence_integration_test.dart`
- `test/support/question_fixture.dart`
- `pubspec.yaml`
- `README.md`
- `docs/README.md`
- `docs/DECISION_LOG.md`
- `docs/PROJECT_STATUS.md`
- `docs/engineering/Local_Persistence_Design.md`
- `docs/operations/Content_Operations_SOP.md`
- `docs/operations/AI_Question_Bank_Workflow.md`

### Technical Decisions

- Use a versioned file contract instead of embedding an AI provider in the app.
- Revalidate content at CLI import and again during app bootstrap.
- Treat pack and question IDs as immutable; revisions require new versioned IDs.
- Preserve human review as the only future path from `draft` to `validated`.
- Compile accepted packs as Flutter assets and persist unseen packs locally in
  one SQLite transaction.

### Validation

- `dart format --output=none --set-exit-if-changed lib tool test` — PASS.
- `flutter analyze` — PASS; no issues found.
- `flutter test` — PASS; 21 tests passed.
- CLI example validation — PASS.
- CLI isolated import, activation, and list smoke test — PASS.
- `flutter build apk --debug` — PASS; bank manifest present in the APK.
- `flutter build ios --debug --no-codesign` — PASS.

### Result

PASS

### Next Step

- Let the owner test AI-generated drafts, then add reviewer signoff, similarity
  checks, and immutable promotion tooling before any production publication.

## 2026-09-06 — Git Flow Branching and Protection

### Objective

Establish `develop` as the active integration branch while keeping `main`
release-only, with documented short-lived branch rules and server-side safety
controls.

### Implemented

- Created and published `develop` from the validated `main` baseline.
- Changed the GitHub default branch from `main` to `develop`.
- Configured local Git Flow branch names and standard `feature/`, `release/`,
  `hotfix/`, `support/`, and version-tag prefixes.
- Added a contributor quick start, detailed Git Flow engineering guide, and pull
  request template.
- Recorded the branching policy in `DEC-004`.
- Protected both long-lived branches by requiring pull requests and resolved
  conversations while disabling force pushes and branch deletion.
- Kept required approvals at zero for the current single-owner repository and
  deferred required status checks until CI provides stable checks.
- Used a short-lived `chore/*` branch and pull request for the final status
  update, exercising the protected workflow.

### Files Changed

- `.github/pull_request_template.md`
- `CONTRIBUTING.md`
- `README.md`
- `docs/README.md`
- `docs/DECISION_LOG.md`
- `docs/engineering/Git_Workflow.md`
- `docs/PROJECT_STATUS.md`
- `docs/IMPLEMENTATION_LOG.md`

### Technical Decisions

- `main` contains release-ready code only; `develop` is the default integration
  branch.
- Normal implementation is reviewed from a short-lived branch into `develop`.
- Releases and hotfixes merge to `main`, receive `vX.Y.Z` tags, and are merged
  back into `develop`.

### Validation

- Local Git Flow configuration inspection — PASS.
- Remote `develop` creation and upstream tracking — PASS.
- GitHub default branch query — PASS; returned `develop`.
- GitHub branch-protection query — PASS for `main` and `develop`.
- Documentation whitespace validation — PASS.

### Result

PASS

### Next Step

- Add CI and promote its stable checks to required branch-protection checks.

## 2026-09-06 — Initial GitHub Publication

### Objective

Place the validated ExamCoach baseline under version control and publish it to the owner-provided GitHub repository without including generated build artifacts.

### Implemented

- Initialized a Git repository with `main` as the primary branch.
- Configured `origin` as `https://github.com/fauzibinfaisal/ExamCoach.git`.
- Confirmed the remote repository had no existing refs before publishing.
- Confirmed Flutter build output, `.dart_tool`, and CocoaPods output are ignored.
- Published the complete Flutter source, tests, mobile platform projects, and documentation baseline.
- Updated the project handoff status to replace repository initialization with CI as the next infrastructure step.

### Files Changed

- `docs/PROJECT_STATUS.md`
- `docs/IMPLEMENTATION_LOG.md`

### Technical Decisions

- Use `main` as the canonical branch and track `origin/main`.
- Keep generated build artifacts out of version control while retaining dependency lockfiles required for reproducible application builds.

### Validation

- Remote preflight with `git ls-remote` — PASS; no existing refs.
- Staged diff whitespace check — PASS.
- Ignore checks for APK/build, `.dart_tool`, and `ios/Pods` — PASS.
- Initial push to `origin/main` — PASS.

### Result

PASS

### Next Step

- Add continuous integration for formatting, analysis, tests, and build smoke checks.

## 2026-09-05 — Repository Audit and Project Handoff Baseline

### Objective

Establish the verified project baseline and persistent handoff documentation before implementation begins.

### Implemented

- Read all supplied business, product, engineering, architecture, and operations documents.
- Confirmed the workspace contains documentation only.
- Verified the local Flutter, Dart, Android, and iOS toolchains.
- Created the required project continuity documents.

### Files Changed

- `docs/PROJECT_STATUS.md`
- `docs/IMPLEMENTATION_LOG.md`
- `docs/DECISION_LOG.md`

### Technical Decisions

- Start with a local/mock end-to-end learning loop because no backend or application exists.
- Keep domain and learning-engine logic pure Dart and separate from presentation code.

### Validation

- `flutter --version` — Flutter 3.44.4 stable.
- `dart --version` — Dart 3.12.2 stable.
- `flutter doctor -v` — PASS.

### Result

PASS

### Next Step

- Scaffold the Flutter application and implement the first deterministic learning loop.

## 2026-09-05 — First End-to-End Learning Loop

### Objective

Deliver the smallest working offline learning loop from local question discovery through updated post-drill insight, with deterministic logic, tests, and both mobile builds.

### Implemented

- Scaffolded Android and iOS targets using Flutter 3.44.4 and Dart 3.12.2.
- Added Bloc/Cubit workflow orchestration, GoRouter navigation, bootstrap composition, and a professional Material 3 theme.
- Added the home screen, tryout question overview, sequential question detail/answer screen, result/weakness screen, explainable recommendation, adaptive drill, and refreshed insight state.
- Added exam-agnostic question and taxonomy models with the full Exam → Test → Domain → Topic → Subtopic → Skill → MicroSkill ID path.
- Added a development-only 12-question TIU pack with provenance, explanation, difficulty, cognitive type, time estimate, validation status, and content version metadata.
- Implemented pure deterministic scoring, configurable weakness analysis, recommendation selection, and adaptive drill composition.
- Added weakness confidence, trend, evidence, classification safeguards, reason-coded recommendations, expected benefit, estimated effort, and algorithm versions.
- Centralized learning/insight analytics names and added a versioned in-memory event sink for the prototype.
- Added unit tests for scoring, weak-evidence safeguards, weakness/trend calculation, recommendation choice, adaptive 70/20/10 selection, and fallback behavior.
- Added a Cubit workflow test and a widget journey covering tryout overview → six answers → result → recommendation → six-question drill → updated insight.
- Replaced generated metadata and README text with ExamCoach-specific values and instructions.

### Files Changed

- `README.md`
- `pubspec.yaml`
- `lib/main.dart`
- `lib/bootstrap/bootstrap.dart`
- `lib/app/app.dart`
- `lib/app/router.dart`
- `lib/core/theme/app_theme.dart`
- `lib/analytics/analytics_events.dart`
- `lib/features/exam/data/mock_question_repository.dart`
- `lib/features/exam/domain/models/answer_record.dart`
- `lib/features/exam/domain/models/question.dart`
- `lib/features/exam/domain/models/taxonomy_path.dart`
- `lib/features/exam/domain/repositories/question_repository.dart`
- `lib/features/home/presentation/home_page.dart`
- `lib/features/learning/application/learning_flow_cubit.dart`
- `lib/features/learning/application/learning_flow_state.dart`
- `lib/features/practice/presentation/question_page.dart`
- `lib/features/practice/presentation/tryout_overview_page.dart`
- `lib/features/result/presentation/result_page.dart`
- `lib/learning_engine/adaptive_drill_engine.dart`
- `lib/learning_engine/recommendation_engine.dart`
- `lib/learning_engine/scoring_engine.dart`
- `lib/learning_engine/weakness_analyzer.dart`
- `lib/learning_engine/models/recommendation.dart`
- `lib/learning_engine/models/score_result.dart`
- `lib/learning_engine/models/weakness_profile.dart`
- `test/features/learning/learning_flow_cubit_test.dart`
- `test/learning_engine/adaptive_drill_engine_test.dart`
- `test/learning_engine/recommendation_engine_test.dart`
- `test/learning_engine/scoring_engine_test.dart`
- `test/learning_engine/weakness_analyzer_test.dart`
- `test/support/question_fixture.dart`
- `test/widget_test.dart`
- `android/app/src/main/AndroidManifest.xml`
- `ios/Runner/Info.plist`
- `docs/PROJECT_STATUS.md`
- `docs/IMPLEMENTATION_LOG.md`
- `docs/DECISION_LOG.md`

### Technical Decisions

- Use the documented Bloc/Cubit and GoRouter stack for workflow and navigation.
- Keep learning calculations pure Dart and dependency-free.
- Treat the local TIU pack as development `draft` content, never as published or officially validated material.
- Use provisional, configuration-driven weakness-v1 parameters until outcome data supports calibration.
- Use largest-remainder allocation to translate the 70/20/10 drill policy into small integer session sizes.
- Prefer unseen questions inside each tier, then deterministically fall back to previous exposure or other tiers to fill a requested drill.

### Validation

- `dart format lib test` — PASS.
- `flutter analyze` — PASS; no issues found.
- `flutter test` — PASS; 11 tests passed.
- `flutter build apk --debug` — PASS.
- `flutter build ios --debug --no-codesign` — PASS.

### Result

PASS

### Next Step

- Implement persistent offline repositories for question packs, active sessions, answers, learning profiles, recommendations, and an idempotent sync outbox.

## 2026-09-05 — Offline Persistence and Interrupted-Session Recovery

### Objective

Make the existing learning loop durable across application restarts while preserving deterministic local scoring and preparing mutations for later backend synchronization.

### Implemented

- Added native SQLite persistence with `sqflite` and dependency-injected database factories.
- Added an explicit schema for question packs, questions, exam sessions, answers, weakness profiles, recommendations, analytics events, and the sync outbox.
- Added schema versioning and a tested migration from v1 to v2 for analytics/outbox storage.
- Added a SQLite-backed question repository that seeds and reloads the development pack using stable IDs and complete metadata.
- Added domain models and repository contracts for persisted learning snapshots, exam sessions, and sync outbox operations.
- Added transactional start-session, answer, completion, profile, recommendation, analytics, and outbox writes.
- Changed the learning workflow to commit each answer before advancing to the next question.
- Added bootstrap restoration of completed history and interrupted active sessions.
- Added a Home resume card that returns the user to the exact next question.
- Preserved previous performance history when starting new tryouts and drills.
- Added deterministic outbox IDs, retry-attempt/error state, sync completion state, and coupled analytics source-state updates.
- Added a transient fallback repository so database bootstrap failure does not prevent the app from launching.
- Added real-file SQLite integration tests for creation, migration, restart, recovery, idempotency, durable analytics, and completed insight restoration.

### Files Changed

- `pubspec.yaml`
- `pubspec.lock`
- `lib/main.dart`
- `lib/bootstrap/bootstrap.dart`
- `lib/analytics/analytics_events.dart`
- `lib/analytics/local_analytics.dart`
- `lib/features/exam/data/local_question_repository.dart`
- `lib/features/exam/domain/models/answer_record.dart`
- `lib/features/exam/domain/models/exam_session.dart`
- `lib/features/home/presentation/home_page.dart`
- `lib/features/learning/application/learning_flow_cubit.dart`
- `lib/features/learning/application/learning_flow_state.dart`
- `lib/features/learning/data/local_learning_persistence_repository.dart`
- `lib/features/learning/data/transient_learning_persistence_repository.dart`
- `lib/features/learning/domain/models/learning_persistence_snapshot.dart`
- `lib/features/learning/domain/repositories/learning_persistence_repository.dart`
- `lib/features/practice/presentation/question_page.dart`
- `lib/features/result/presentation/result_page.dart`
- `lib/services/database/exam_coach_database.dart`
- `lib/services/sync/domain/sync_outbox_item.dart`
- `lib/services/sync/domain/sync_outbox_repository.dart`
- `test/features/learning/learning_flow_cubit_test.dart`
- `test/persistence/local_persistence_integration_test.dart`
- `ios/Podfile.lock`
- `docs/README.md`
- `docs/engineering/Database_ERD.md`
- `docs/engineering/Local_Persistence_Design.md`
- `docs/PROJECT_STATUS.md`
- `docs/IMPLEMENTATION_LOG.md`
- `docs/DECISION_LOG.md`

### Technical Decisions

- Use `sqflite` rather than a generated ORM for the initial mobile-only persistence slice.
- Keep database types and serialization inside data modules; the learning engine remains persistence-independent.
- Treat local state as immediately authoritative and queue later remote delivery through an idempotent outbox.
- Make analytics best-effort for the learning flow while still persisting successful local writes transactionally.
- Fail explicitly on unknown migrations instead of deleting or recreating the database.

### Validation

- `dart format lib test` — PASS.
- `flutter analyze` — PASS; no issues found.
- `flutter test` — PASS; 15 tests passed.
- SQLite real-file integration suite — PASS.
- `flutter build apk --debug` — PASS with native SQLite plugin.
- `flutter build ios --debug --no-codesign` — PASS with CocoaPods/native SQLite plugin.

### Result

PASS

### Next Step

- Add skip/change/cancel/review behavior, followed by a connectivity-aware sync worker over the existing outbox contract.
