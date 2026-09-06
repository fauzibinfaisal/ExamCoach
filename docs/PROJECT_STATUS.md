# ExamCoach Project Status

## Current Phase

Phase 8 connectivity-aware outbox delivery is complete. The next phase is human
content review, similarity checking, and immutable publication tooling for the
question bank.

## Overall Progress

The deterministic learning loop now runs offline and survives application/database restarts:

```text
Home → Tryout overview → Answer or skip → Local commit → Pre-submit review
→ Edit or explicitly finish → Score → Answer/explanation review
→ Weakness analysis → Recommendation → Adaptive drill
→ Updated insight → Persisted history
```

Question packs, active sessions, answers, results, weakness profiles, recommendations, analytics events, and sync operations are stored in versioned SQLite. A tested provider-neutral worker can batch, retry, acknowledge, dead-letter, and prune outbox delivery when a remote gateway is supplied. The authenticated Firebase gateway, cross-device synchronization, runtime AI, subscriptions, and production content are not implemented yet.

External AI tools can now produce versioned JSON question packs for deterministic local validation and asset import. ExamCoach does not call AI at runtime; generated content remains `draft` and is revalidated before transactional SQLite ingestion.

## 12-Step Delivery Roadmap

| Step | Milestone | Status |
|---:|---|---|
| 1 | Repository audit and persistent handoff baseline | Complete |
| 2 | Flutter shell and deterministic end-to-end learning loop | Complete |
| 3 | Offline SQLite persistence, recovery, analytics queue, and outbox | Complete |
| 4 | GitHub repository publication | Complete |
| 5 | Protected Git Flow with `develop` integration | Complete |
| 6 | Provider-neutral external-AI question-bank ingestion | Complete |
| 7 | Skip/edit/cancel/expiry and pre/post-result review | Complete |
| 8 | Connectivity-aware sync worker, retry, acknowledgement, and conflict policy | Complete |
| 9 | Human content review, similarity checks, and immutable publication | Next |
| 10 | Firebase authentication, remote data, and cross-device recovery | Planned |
| 11 | Structured AI Coach, quota, entitlements, and subscriptions | Planned |
| 12 | Product analytics, accessibility, performance, CI, and release readiness | Planned |

Current position: **Step 8 of 12 complete (66.7%)**. Integration target is `develop`;
`main` remains unchanged until owner testing and release approval.

## Completed

- Read and reconciled the complete product and engineering context pack under `docs/`.
- Scaffolded a Flutter 3.44.4 Android/iOS app with Bloc/Cubit and GoRouter.
- Implemented the full local tryout → insight → drill → updated-insight UI and deterministic learning engine.
- Added exam-agnostic taxonomy, question, answer, session, score, weakness, and recommendation models.
- Added a 12-question local TIU prototype pack with stable IDs, metadata, versions, provenance, explanations, and explicit `draft` status.
- Added SQLite through `sqflite` for native Android/iOS persistence.
- Added a dependency-injected database boundary using native SQLite in production and SQLite FFI in tests.
- Added schema v1 for content and learning data, plus a tested v1→v2 migration for durable analytics and sync outbox tables.
- Persisted the prototype question pack into the local content repository.
- Persisted session state and each answer transactionally before advancing the UI.
- Restored interrupted sessions at the exact next question after closing and reopening the database.
- Persisted completed answer history, latest score, weakness profiles, and recommendation across relaunches.
- Added a Home card that exposes and resumes an interrupted offline session.
- Added idempotent outbox operation IDs for session start, answers, completion, and analytics.
- Added failed-attempt tracking and synced-state handling for the outbox.
- Persisted analytics locally and transactionally queued each event for later upload.
- Preserved graceful startup: a database failure is reported and falls back to the transient learning repository.
- Added integration coverage using real temporary SQLite files.
- Produced Android and unsigned iOS debug builds with the native SQLite plugin.
- Initialized Git on `main` and published the project to `https://github.com/fauzibinfaisal/ExamCoach.git`.
- Established `develop` as the default integration branch with standard Git Flow branch prefixes.
- Protected `main` and `develop` with pull-request, resolved-conversation, no-force-push, and no-deletion rules.
- Added the contributor workflow, Git Flow engineering guide, and pull request template.
- Added an AI-provider-neutral JSON contract, prompt template, example pack, validator, importer, and bank manifest.
- Added deterministic checks for schema version, identifiers, answer references, taxonomy, duplicates, durations, authorship, provenance, and six-question tryout selection.
- Enforced `draft` status and null reviewer metadata for all AI-generated imports.
- Added manifest-selected active packs while retaining older packs for session/history integrity.
- Added SQLite schema v3 for pack generation, author, reviewer, and immutable tryout-selection metadata.
- Added tested v1→v2→v3 migration and idempotent generated-pack import.
- Rebuilt Android and iOS debug artifacts with the question-bank asset manifest.
- Added durable answer skipping, backwards navigation, saved-answer preselection, and sticky answer-change tracking.
- Added pre-submit review with explicit completion and edit-any-question navigation.
- Added confirmation-based cancellation and 24-hour inactive-session expiry that exclude partial responses from learning history.
- Added exact recovery into an active question or completed-response review state.
- Added post-result selected/correct answer and explanation review behind an entitlement-ready access policy.
- Added SQLite schema v4, replaceable answer/progress outbox payloads, terminal session operations, and tested v1→v4 migration.
- Added centralized cancellation, expiry, skip, answer-change, and question-review analytics.
- Added full Cubit, SQLite, and widget coverage for the new lifecycle; the suite now contains 27 passing tests.
- Rebuilt Android and unsigned iOS debug artifacts after the session-control milestone.
- Added a provider-neutral remote gateway boundary and a real
  `connectivity_plus` transport monitor.
- Added a single-flight sync worker with stable ready-queue ordering, bounded
  25-operation batches, and at most ten batches per run.
- Added accepted, duplicate, and superseded acknowledgement handling without
  allowing remote delivery to rewrite local deterministic learning state.
- Added five-attempt exponential retry from five seconds to fifteen minutes,
  missing-acknowledgement recovery, permanent-rejection quarantine, and durable
  dead letters.
- Added startup/reconnect coordination and a seven-day transactional retention
  policy for acknowledged outbox and synced analytics records.
- Added SQLite schema v5 delivery metadata and tested both v1→v5 and direct
  v4→v5 migrations.
- Added fake-remote and real-SQLite sync coverage; the complete suite now
  contains 37 passing tests.
- Adopted pre-1.0 versioning and set the current development build to
  `0.8.0+8`.
- Rebuilt Android and unsigned iOS debug artifacts and verified both embed
  version `0.8.0`, build `8`.

## Currently Working On

No implementation is in progress. Step 8 is closed and validated for integration
into `develop`. `main` remains unchanged.

## Next Steps

1. Define the human reviewer checklist and persist reviewer identity, timestamp,
   review notes, and source/provenance decisions.
2. Add deterministic exact-duplicate and normalized-similarity checks across
   draft and existing question packs.
3. Add an immutable `draft` → `validated`/`published` promotion command that
   refuses incomplete reviews and never edits accepted IDs in place.
4. Add reviewer workflow tests and update the content-operations guide with a
   repeatable manual QA procedure.
5. Integrate an authenticated Firebase gateway, security rules, and cross-device
   recovery in Step 10 without coupling sync to local scoring.
6. Confirm final Android/iOS application identifiers before release configuration.
7. Add CI for formatting, static analysis, tests, and mobile build smoke checks,
   then make those checks required on `main` and `develop`.

## Blockers

- Production content cannot ship until a human reviewer validates correctness, ambiguity, distractors, explanations, taxonomy, difficulty, and provenance.
- Final application identifiers require owner confirmation before store/release setup; the current generated IDs are suitable for development builds only.

## Known Issues

- The worker has no production `SyncRemoteGateway` or bootstrap registration;
  queued data remains local until authenticated Firebase integration in Step 10.
- Dead letters are durable but do not yet have operator inspection or controlled
  re-drive tooling.
- The 24-hour session expiry is a provisional local default and is not remotely configurable yet.
- Explanation access has a policy boundary, but the development policy allows all draft explanations until trusted subscription entitlements exist.
- Database bootstrap fallback is transient; data created during fallback is intentionally not durable.
- Weakness v1 does not yet model recency decay, consistency across sessions, or repeated-attempt penalties separately.
- Adaptive drill v1 does not yet implement spaced repetition, fatigue, or difficulty progression.
- Prototype questions are `draft`, not published content.
- Android uses `id.examcoach.exam_coach`; iOS uses generated identifier `id.examcoach.examCoach`. These are provisional.
- AI pack validation verifies structure and internal consistency, not factual correctness, originality, ambiguity, or calibrated difficulty.
- AI pack promotion to `validated` is intentionally not implemented; generated packs remain development-only drafts.
- New asset packs require a fresh app build before they can reach an installed device.
- Cross-device inbound conflict reconciliation is not implemented; Step 8 covers
  explicit upload acknowledgement and supersession only.

## Technical Decisions

- Pure Dart learning-engine modules remain the source of truth; widgets, persistence, backend, and AI do not calculate official learning decisions.
- Bloc/Cubit orchestrates workflow; GoRouter owns navigation.
- SQLite through `sqflite` is the initial mobile persistence layer; SQL migrations are explicit and fail closed when a migration is missing.
- `sqflite_common_ffi` is a development-only dependency used for real SQLite integration tests.
- Question access remains behind a synchronous repository contract backed by an initialized local cache.
- Learning mutations and their outbox entries share transaction boundaries.
- Stable operation IDs make outbox retries idempotent.
- Network availability is only a sync trigger; failed requests remain retryable
  and never block local scoring, progression, or recovery.
- Remote batch outcomes are explicit: accepted, duplicate, and superseded close
  delivery; transient failures retry; permanent rejection or attempt exhaustion
  enters a durable dead letter.
- A superseded upload is acknowledged without mutating local learning evidence;
  cross-device reconciliation is a separate authenticated flow.
- Acknowledged outbox and synced analytics records are retained for seven days,
  then pruned transactionally; pending and dead-letter records are preserved.
- Analytics failures never block scoring or progression; successful local analytics writes are durable and queued.
- `main` is the release branch, `develop` is the default integration branch, and `origin` points to `https://github.com/fauzibinfaisal/ExamCoach.git`.
- Normal implementation uses `feature/*` or `bugfix/*` from `develop`; releases and production fixes use `release/*` and `hotfix/*` respectively.
- External AI integration is file-based and provider-neutral; no AI credentials or runtime AI dependency enter the mobile app.
- `ai_question_pack_v1` is the canonical generated-content contract, and accepted pack/question IDs are immutable.
- The question-bank manifest selects the active tryout; unseen bundled packs are inserted into SQLite transactionally.
- Machine validation cannot promote AI content beyond `draft`; human review remains mandatory.
- A response is either an answer or an explicit skip; scoring is review-gated and runs only after explicit session completion.
- Cancelled and expired session rows are retained for audit/sync, while their partial answers are excluded from learning evidence.
- Active sessions expire after a provisional 24 hours of inactivity during bootstrap recovery.
- Explanation visibility is routed through `QuestionReviewAccessPolicy`; the current development policy allows all local draft explanations.
- SQLite schema v5 adds delivery scheduling, acknowledgement, remote-revision,
  dead-letter, and retention metadata.
- Development builds use `0.MINOR.PATCH+BUILD`; `1.0.0` is reserved for the first
  owner-approved production release. Database schema versions remain separate.
- Weakness v1 uses configurable 65% accuracy, 20% speed, and 15% difficulty-handling weights, with two samples required for weak classification and five for full confidence.
- Adaptive drill v1 uses largest-remainder allocation for the configurable 70/20/10 policy and prioritizes unseen questions within each tier.

## Files Recently Changed

- `lib/services/sync/application/sync_worker.dart`
- `lib/services/sync/application/sync_coordinator.dart`
- `lib/services/sync/data/connectivity_plus_monitor.dart`
- `lib/services/sync/domain/connectivity_monitor.dart`
- `lib/services/sync/domain/sync_remote_gateway.dart`
- `lib/services/sync/domain/sync_retry_policy.dart`
- `lib/services/sync/domain/sync_run_summary.dart`
- `test/services/sync/sync_worker_integration_test.dart`
- `test/services/sync/sync_coordinator_test.dart`
- `docs/engineering/Sync_Architecture.md`
- `docs/engineering/Release_Versioning.md`
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
- `lib/features/practice/presentation/session_cancel_dialog.dart`
- `lib/features/practice/presentation/session_review_page.dart`
- `lib/features/practice/presentation/tryout_overview_page.dart`
- `lib/features/result/domain/question_review_access_policy.dart`
- `lib/features/result/presentation/answer_review_page.dart`
- `lib/features/result/presentation/result_page.dart`
- `lib/services/database/exam_coach_database.dart`
- `lib/services/sync/domain/sync_outbox_item.dart`
- `lib/services/sync/domain/sync_outbox_repository.dart`
- `test/features/learning/learning_flow_cubit_test.dart`
- `test/persistence/local_persistence_integration_test.dart`
- `test/widget_test.dart`
- `ios/Podfile.lock`
- `docs/engineering/Local_Persistence_Design.md`
- `docs/engineering/Session_Controls_and_Review.md`
- `docs/engineering/Analytics_Event_Map.md`
- `docs/engineering/Database_ERD.md`
- `lib/features/exam/data/bundled_question_bank_loader.dart`
- `lib/features/exam/data/question_bank_manifest.dart`
- `lib/features/exam/data/question_pack_codec.dart`
- `lib/features/exam/domain/models/question_pack.dart`
- `tool/question_bank.dart`
- `assets/question_bank/manifest.json`
- `content/question_pack.schema.json`
- `content/ai_question_prompt.md`
- `content/examples/question_pack.example.json`
- `test/features/exam/question_pack_codec_test.dart`
- `docs/operations/AI_Question_Bank_Workflow.md`
- `docs/engineering/Git_Workflow.md`
- `docs/PROJECT_STATUS.md`
- `docs/IMPLEMENTATION_LOG.md`
- `docs/DECISION_LOG.md`
- `CONTRIBUTING.md`
- `.github/pull_request_template.md`

## Last Validation

- 2026-09-05: `dart format lib test` — PASS.
- 2026-09-05: `flutter analyze` — PASS; no issues found.
- 2026-09-05: `flutter test` — PASS; 15 tests passed.
- 2026-09-05: SQLite integration suite — PASS; schema, v1→v2 migration, restart recovery, history, analytics, and outbox verified.
- 2026-09-05: `flutter build apk --debug` — PASS; `build/app/outputs/flutter-apk/app-debug.apk` created.
- 2026-09-05: `flutter build ios --debug --no-codesign` — PASS; `build/ios/iphoneos/Runner.app` created.
- 2026-09-06: GitHub publication — PASS; `main` created on `origin` and local tracking configured.
- 2026-09-06: Git Flow setup — PASS; `develop` is the GitHub default, both long-lived branches are protected, and prefix configuration is present locally.
- 2026-09-06: `dart format --output=none --set-exit-if-changed lib tool test` — PASS.
- 2026-09-06: `flutter analyze` — PASS; no issues found.
- 2026-09-06: `flutter test` — PASS; 21 tests passed.
- 2026-09-06: AI question CLI validation/import/list smoke test — PASS in an isolated temporary bank.
- 2026-09-06: `flutter build apk --debug` — PASS; bundled question-bank manifest verified inside the APK.
- 2026-09-06: `flutter build ios --debug --no-codesign` — PASS.
- 2026-09-06: `dart format lib test` — PASS for Step 7 session controls and review.
- 2026-09-06: `flutter analyze` — PASS; no issues found after Step 7.
- 2026-09-06: `flutter test` — PASS; 27 tests passed, including skip/edit/cancel/expiry/review and SQLite v1→v4 migration.
- 2026-09-06: `flutter build apk --debug` — PASS; latest installable debug APK created.
- 2026-09-06: `flutter build ios --debug --no-codesign` — PASS; latest unsigned `Runner.app` created.
- 2026-09-06: Git Flow integration — PASS; pull request #3 merged Step 7 into `develop`, the feature branch was removed, and `main` remained unchanged.
- 2026-09-06: `dart format lib test` — PASS for Step 8 sync delivery.
- 2026-09-06: `flutter analyze` — PASS; no issues found after Step 8.
- 2026-09-06: Focused SQLite/sync suite — PASS; 17 tests passed.
- 2026-09-06: `flutter test` — PASS; 37 tests passed, including offline reconnect,
  acknowledgement variants, retry/dead-letter, uncertain delivery, retention,
  and v1/v4→v5 migration.
- 2026-09-06: `flutter build apk --debug` — PASS; installable 155 MB debug APK
  embeds version `0.8.0`, build `8` (SHA-256
  `b439675d71a60b1b02f1d3735540b50562da89f9cce0590acc4087f2afb0b417`).
- 2026-09-06: `flutter build ios --debug --no-codesign` — PASS; unsigned
  `Runner.app` embeds version `0.8.0`, build `8`.

## Documentation Updated

- 2026-09-05: Added `engineering/Local_Persistence_Design.md` with schema, transactions, recovery, outbox, migration, and deferred work.
- 2026-09-05: Updated project status, implementation log, decision log, and documentation reading order.
- 2026-09-06: Recorded repository initialization, GitHub publication, and the CI follow-up.
- 2026-09-06: Added the Git Flow guide, contributor guide, PR template, decision record, and branch-protection handoff.
- 2026-09-06: Added the external-AI question generation/import guide, JSON schema, prompt, example, persistence changes, decision record, and validation results.
- 2026-09-06: Added the session-control/review design and manual QA guide; updated roadmap, lifecycle, schema v4, analytics, ERD, decision, and implementation records.
- 2026-09-06: Added the sync architecture and pre-1.0 versioning guides; updated
  roadmap, persistence schema v5, backend boundary, ERD, analytics, contributor,
  decision, and implementation records.

## Notes For Next AI Session

Read this file, `IMPLEMENTATION_LOG.md`, `DECISION_LOG.md`,
`engineering/Git_Workflow.md`, `engineering/Release_Versioning.md`,
`engineering/Local_Persistence_Design.md`, `engineering/Sync_Architecture.md`,
`engineering/Session_Controls_and_Review.md`, and
`operations/AI_Question_Bank_Workflow.md` before changing code. Keep solo
development integrated through short-lived branches into `develop`, and merge to
`main` only after full validation and owner approval. Step 8 of 12 is complete;
begin Step 9 with human review evidence, similarity checks, and immutable content
promotion. Do not register a production sync gateway before authenticated remote
ownership exists, do not couple remote or AI failures to local scoring, and do
not promote generated content without human review.
