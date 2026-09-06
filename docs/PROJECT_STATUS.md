# ExamCoach Project Status

## Current Phase

Phase 5 offline persistence foundation is complete. The next phase is session controls, question review, and the first sync worker boundary.

## Overall Progress

The deterministic learning loop now runs offline and survives application/database restarts:

```text
Home → Tryout overview → Question detail → Answer → Local commit
→ Score → Weakness analysis → Recommendation → Adaptive drill
→ Updated insight → Persisted history
```

Question packs, active sessions, answers, results, weakness profiles, recommendations, analytics events, and sync operations are stored in versioned SQLite. Backend synchronization, authentication, AI, subscriptions, and production content are not implemented yet.

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
8. Route the prototype content through human review and publish only a validated pack.
9. Confirm final Android/iOS application identifiers before release configuration.
10. Initialize version control when repository ownership and remote workflow are confirmed.

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
- The workspace is not a Git repository.

## Technical Decisions

- Pure Dart learning-engine modules remain the source of truth; widgets, persistence, backend, and AI do not calculate official learning decisions.
- Bloc/Cubit orchestrates workflow; GoRouter owns navigation.
- SQLite through `sqflite` is the initial mobile persistence layer; SQL migrations are explicit and fail closed when a migration is missing.
- `sqflite_common_ffi` is a development-only dependency used for real SQLite integration tests.
- Question access remains behind a synchronous repository contract backed by an initialized local cache.
- Learning mutations and their outbox entries share transaction boundaries.
- Stable operation IDs make outbox retries idempotent.
- Analytics failures never block scoring or progression; successful local analytics writes are durable and queued.
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
- `docs/PROJECT_STATUS.md`
- `docs/IMPLEMENTATION_LOG.md`
- `docs/DECISION_LOG.md`

## Last Validation

- 2026-09-05: `dart format lib test` — PASS.
- 2026-09-05: `flutter analyze` — PASS; no issues found.
- 2026-09-05: `flutter test` — PASS; 15 tests passed.
- 2026-09-05: SQLite integration suite — PASS; schema, v1→v2 migration, restart recovery, history, analytics, and outbox verified.
- 2026-09-05: `flutter build apk --debug` — PASS; `build/app/outputs/flutter-apk/app-debug.apk` created.
- 2026-09-05: `flutter build ios --debug --no-codesign` — PASS; `build/ios/iphoneos/Runner.app` created.

## Documentation Updated

- 2026-09-05: Added `engineering/Local_Persistence_Design.md` with schema, transactions, recovery, outbox, migration, and deferred work.
- 2026-09-05: Updated project status, implementation log, decision log, and documentation reading order.

## Notes For Next AI Session

Read this file, `IMPLEMENTATION_LOG.md`, `DECISION_LOG.md`, and `engineering/Local_Persistence_Design.md` before changing code. Start with skip/change/cancel/review behavior, then implement the sync worker against the existing outbox contract. Do not couple remote failures to local scoring, and do not promote the prototype pack beyond `draft` without human review.
