# ExamCoach Project Status

## Current Phase

Phase 6 provider-neutral AI draft ingestion is complete. The next phase is session controls, human question review, and the first sync worker boundary.

## Overall Progress

The deterministic learning loop now runs offline and survives application/database restarts:

```text
Home → Tryout overview → Question detail → Answer → Local commit
→ Score → Weakness analysis → Recommendation → Adaptive drill
→ Updated insight → Persisted history
```

Question packs, active sessions, answers, results, weakness profiles, recommendations, analytics events, and sync operations are stored in versioned SQLite. Backend synchronization, authentication, AI, subscriptions, and production content are not implemented yet.

External AI tools can now produce versioned JSON question packs for deterministic local validation and asset import. ExamCoach does not call AI at runtime; generated content remains `draft` and is revalidated before transactional SQLite ingestion.

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

## Currently Working On

No implementation is in progress. The offline persistence milestone is closed and validated.

## Next Steps

1. Add explicit answer skipping and answer-change tracking using the centralized `question_skipped` and `answer_changed` events.
2. Add session cancellation and expiry, including safe resolution of abandoned active sessions.
3. Add post-session question review with selected answer, correct answer, and explanation behind an entitlement-ready access policy.
4. Implement a connectivity observer and sync worker that consumes `SyncOutboxRepository` in batches.
5. Define retry backoff, remote acknowledgement, dead-letter handling, and conflict resolution without changing local learning results.
6. Add a fake-remote integration suite for offline → reconnect → acknowledge → local cleanup behavior.
7. Add retention/pruning for completed sessions, synced analytics, and synced outbox records.
8. Build human review, similarity checking, and immutable promotion tooling; publish only reviewer-approved packs.
9. Confirm final Android/iOS application identifiers before release configuration.
10. Add CI for formatting, static analysis, tests, and mobile build smoke checks, then make those checks required on `main` and `develop`.

## Blockers

- Production content cannot ship until a human reviewer validates correctness, ambiguity, distractors, explanations, taxonomy, difficulty, and provenance.
- Final application identifiers require owner confirmation before store/release setup; the current generated IDs are suitable for development builds only.

## Known Issues

- The outbox is durable, but there is no connectivity observer or remote sync worker yet.
- Synced data is not pruned, so local storage can grow over time.
- Session cancellation, expiry, answer skipping, and answer-change analytics are not implemented yet.
- Question review and entitlement-aware explanation access are not implemented yet.
- Database bootstrap fallback is transient; data created during fallback is intentionally not durable.
- Weakness v1 does not yet model recency decay, consistency across sessions, or repeated-attempt penalties separately.
- Adaptive drill v1 does not yet implement spaced repetition, fatigue, or difficulty progression.
- Prototype questions are `draft`, not published content.
- Android uses `id.examcoach.exam_coach`; iOS uses generated identifier `id.examcoach.examCoach`. These are provisional.
- AI pack validation verifies structure and internal consistency, not factual correctness, originality, ambiguity, or calibrated difficulty.
- AI pack promotion to `validated` is intentionally not implemented; generated packs remain development-only drafts.
- New asset packs require a fresh app build before they can reach an installed device.

## Technical Decisions

- Pure Dart learning-engine modules remain the source of truth; widgets, persistence, backend, and AI do not calculate official learning decisions.
- Bloc/Cubit orchestrates workflow; GoRouter owns navigation.
- SQLite through `sqflite` is the initial mobile persistence layer; SQL migrations are explicit and fail closed when a migration is missing.
- `sqflite_common_ffi` is a development-only dependency used for real SQLite integration tests.
- Question access remains behind a synchronous repository contract backed by an initialized local cache.
- Learning mutations and their outbox entries share transaction boundaries.
- Stable operation IDs make outbox retries idempotent.
- Analytics failures never block scoring or progression; successful local analytics writes are durable and queued.
- `main` is the release branch, `develop` is the default integration branch, and `origin` points to `https://github.com/fauzibinfaisal/ExamCoach.git`.
- Normal implementation uses `feature/*` or `bugfix/*` from `develop`; releases and production fixes use `release/*` and `hotfix/*` respectively.
- External AI integration is file-based and provider-neutral; no AI credentials or runtime AI dependency enter the mobile app.
- `ai_question_pack_v1` is the canonical generated-content contract, and accepted pack/question IDs are immutable.
- The question-bank manifest selects the active tryout; unseen bundled packs are inserted into SQLite transactionally.
- Machine validation cannot promote AI content beyond `draft`; human review remains mandatory.
- Weakness v1 uses configurable 65% accuracy, 20% speed, and 15% difficulty-handling weights, with two samples required for weak classification and five for full confidence.
- Adaptive drill v1 uses largest-remainder allocation for the configurable 70/20/10 policy and prioritizes unseen questions within each tier.

## Files Recently Changed

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
- `docs/engineering/Local_Persistence_Design.md`
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

## Documentation Updated

- 2026-09-05: Added `engineering/Local_Persistence_Design.md` with schema, transactions, recovery, outbox, migration, and deferred work.
- 2026-09-05: Updated project status, implementation log, decision log, and documentation reading order.
- 2026-09-06: Recorded repository initialization, GitHub publication, and the CI follow-up.
- 2026-09-06: Added the Git Flow guide, contributor guide, PR template, decision record, and branch-protection handoff.
- 2026-09-06: Added the external-AI question generation/import guide, JSON schema, prompt, example, persistence changes, decision record, and validation results.

## Notes For Next AI Session

Read this file, `IMPLEMENTATION_LOG.md`, `DECISION_LOG.md`, `engineering/Git_Workflow.md`, `engineering/Local_Persistence_Design.md`, and `operations/AI_Question_Bank_Workflow.md` before changing code. Keep current solo development on `develop` and merge to `main` only after full validation and owner approval. Begin with skip/change/cancel/review behavior, then implement the sync worker against the existing outbox contract. Do not couple remote or AI failures to local scoring, and do not promote any generated pack beyond `draft` without human review.
