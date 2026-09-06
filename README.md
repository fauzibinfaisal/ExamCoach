# ExamCoach

ExamCoach is a Flutter application for personalized, insight-led exam preparation. The current milestone provides a durable offline-first learning loop using local draft content:

```text
Tryout overview → Answer questions → Score → Weakness analysis
→ Explainable recommendation → Adaptive drill → Updated insight
```

SQLite stores downloaded prototype content, active sessions, answers, learning history, recommendations, analytics, and an idempotent sync outbox. An interrupted tryout can be resumed after relaunch.

The deterministic learning engine is the source of truth. AI integration is intentionally not part of scoring, correctness, weakness analysis, or question selection.

## Run

```bash
flutter pub get
flutter run
```

## Validate

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --debug --no-codesign
```

## Project handoff

Read these documents before changing implementation:

- `docs/PROJECT_STATUS.md`
- `docs/IMPLEMENTATION_LOG.md`
- `docs/DECISION_LOG.md`
- `docs/README.md`

The bundled question pack is development-only, marked `draft`, and must not be treated as published exam content without the documented human review workflow.
