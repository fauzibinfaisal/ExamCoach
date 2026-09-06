# AI Question Bank Workflow

## Purpose

This workflow accepts draft questions from any external AI provider without
coupling ExamCoach to that provider. AI output is treated as untrusted content:
it must pass deterministic validation, remains `draft`, and is bundled into the
mobile app before SQLite imports it locally.

```text
External AI → JSON draft → Local validator → Asset bank manifest
→ App rebuild/reinstall → Transactional SQLite import → Draft tryout
```

Passing the validator proves structural consistency only. It does not prove
factual correctness, originality, appropriate difficulty, or absence of
ambiguity.

## 1. Generate a Draft with Any AI

1. Open `content/ai_question_prompt.md`.
2. Replace the bracketed exam, test, topic, count, and author placeholders.
3. Attach `content/question_pack.schema.json` to the AI conversation when the
   provider supports file attachments.
4. Ask the AI to follow the prompt and return JSON only.
5. Save the unmodified response as a `.json` file outside
   `assets/question_bank/`, for example `~/Downloads/tiu-numerik-v1.json`.

The known-good shape is demonstrated in
`content/examples/question_pack.example.json`. Do not copy its sample generator
identity into a real pack; record the actual provider, model, author, and UTC
generation time.

## 2. Validate the AI Output

From the repository root, run:

```bash
dart run tool/question_bank.dart validate /absolute/path/to/pack.json
```

The command exits unsuccessfully and lists validation errors when it finds
malformed JSON, unsupported schema versions, bad IDs, broken answer references,
duplicate options/questions, incomplete taxonomy, invalid durations, missing
provenance, inconsistent authorship, non-draft status, or an invalid six-question
tryout selection.

Fix the source file or ask the AI to regenerate it, then validate again. Never
remove a validation rule simply to accept one AI response.

## 3. Import into the Bank

To add a valid pack without changing the active tryout:

```bash
dart run tool/question_bank.dart import /absolute/path/to/pack.json
```

To add it and make its selected six questions the active development tryout:

```bash
dart run tool/question_bank.dart import /absolute/path/to/pack.json --activate
```

Inspect the current bank:

```bash
dart run tool/question_bank.dart list
```

Import is intentionally non-destructive. Existing pack IDs, destination files,
and duplicate question IDs are rejected rather than overwritten. To revise a
pack, increment its version and create new immutable IDs, for example change
`pack_cpns_tiu_numerik_v1` to `pack_cpns_tiu_numerik_v2` and use `v2` question
IDs.

## 4. Load It into the App

The importer writes the canonical pack into `assets/question_bank/` and updates
its manifest. Assets are compiled into the app, so perform a fresh run or build:

```bash
flutter test
flutter run
```

For a physical device APK test:

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

On startup, ExamCoach validates the bundled pack again and imports any unseen
pack transactionally into SQLite schema v3. Previously imported packs are kept
for session/history integrity. The manifest decides which pack supplies the six
initial tryout questions.

## 5. Human Review Gate

Every generated pack remains a development-only `draft`. A human reviewer must
verify at least:

- mathematical/factual correctness and exactly one defensible answer;
- prompt clarity, ambiguity, distractor quality, and explanation sufficiency;
- taxonomy mapping, estimated time, and difficulty calibration;
- originality, licensing/provenance, and unacceptable similarity risk;
- language, inclusivity, and suitability for the intended exam.

The current importer deliberately refuses `validated` AI packs. Promotion and
reviewer-signoff tooling is a separate future milestone; until then, generated
packs must not be released as official ExamCoach content.

## Failure Safety

- Invalid assets fail during bootstrap and trigger the existing transient
  fallback rather than partially modifying SQLite.
- A pack insert and all of its question inserts share one database transaction.
- Stable pack/question IDs prevent duplicate import and preserve answer history.
- The AI is never called at runtime and never participates in scoring, weakness
  calculation, recommendations, or answer correctness.
