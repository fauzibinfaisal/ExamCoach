# ExamCoach — Human Question Review and Publication Workflow

## Purpose

Move an imported AI question pack through an auditable, human-controlled
`draft → validated → published` lifecycle without editing accepted content or
IDs in place.

Passing structural validation or a similarity scan is not human approval. An AI
assistant, including the AI that generated the questions, must not fill or
approve the review record. The named human reviewer is accountable for every
checked criterion.

## Lifecycle

```text
AI-generated JSON (schema v1, draft)
  → structural validation
  → exact-ID and normalized-similarity gate
  → immutable asset-bank import
  → human review record bound to content SHA-256
  → validated artifact (schema v2)
  → explicit publisher action
  → published artifact (schema v2)
```

Each promotion creates a new file and repoints the manifest. Previous draft and
validated files remain on disk for audit. Pack IDs, question IDs, question text,
options, correct answers, taxonomy, explanations, versions, generation data,
and provenance are included in the SHA-256 content fingerprint and cannot
change during promotion.

## 1. Import the Draft

Generate and validate the pack using `AI_Question_Bank_Workflow.md`, then import
it:

```bash
dart run tool/question_bank.dart import /absolute/path/to/pack.json
dart run tool/question_bank.dart list
```

Import rejects duplicate IDs, normalized exact prompt matches, and prompt
similarity at or above `0.82`, both within the new pack and against every pack
currently referenced by the bank manifest.

## 2. Inspect Similarity

For an imported pack:

```bash
dart run tool/question_bank.dart similarity <pack_id>
```

The deterministic scanner lowercases prompt text, removes punctuation, collapses
whitespace, builds three-token shingles, and calculates Jaccard similarity.
Exact normalized matches always fail. Short prompts use normalized token sets.

This heuristic is a blocking warning system, not proof of originality or legal
clearance. The reviewer must still inspect wording, source material, licensing,
and conceptual similarity.

If the gate fails, revise the source as a new content version with new immutable
pack and question IDs. Do not weaken the threshold or overwrite the existing
draft.

## 3. Create the Review Record

Use a stable lowercase `snake_case` reviewer identity:

```bash
dart run tool/question_bank.dart review-template <pack_id> \
  --reviewer <reviewer_id> \
  --output reviews/<pack_id>.review.json
```

The generated file follows `content/question_review.schema.json`. It already
contains the pack ID, immutable content SHA-256, reviewer identity, complete
question-ID scope, and every required checklist key. It intentionally starts
with `reviewedAt: null`, `decision: pending`, blank notes, and all checks set to
`false`.

## 4. Perform the Human Review

Open every question and verify the following before changing a check to `true`:

| Check | Required evidence |
|---|---|
| `factualCorrectness` | Recalculate or verify facts independently |
| `singleDefensibleAnswer` | Exactly one option is defensibly correct |
| `promptClarity` | No missing assumptions or ambiguous wording |
| `distractorQuality` | Wrong options are plausible but clearly incorrect |
| `explanationQuality` | Explanation proves the answer and teaches the method |
| `taxonomyAccuracy` | Exam through micro-skill mapping is correct |
| `difficultyCalibration` | Difficulty and estimated time are reasonable |
| `languageQuality` | Indonesian grammar, notation, and terminology are sound |
| `inclusivity` | No discriminatory, unsafe, or unsuitable framing |
| `provenanceRights` | Source/licensing/originality basis is documented |
| `similarityRisk` | Machine matches and conceptual similarity were reviewed |

Then fill:

- `reviewedAt`: actual completion time in UTC ISO-8601, for example
  `2026-09-06T08:30:00Z`;
- `decision`: `approved` only when every question passes;
- `notes`: a meaningful summary of the review;
- `provenanceDecision`: one of `original`, `licensed`, `publicDomain`, or
  `aiGeneratedOriginal`;
- `provenanceNotes`: the actual source/right-to-use reasoning; and
- every checklist value: `true` only after completing that check.

Do not change `packId`, `contentSha256`, or `reviewedQuestionIds`. A rejected or
corrected pack must become a new content version with new IDs.

## 5. Promote to Validated

```bash
dart run tool/question_bank.dart promote <pack_id> \
  --to validated \
  --review reviews/<pack_id>.review.json
```

Promotion fails without a matching digest, exact question scope, UTC review
time, approved decision, meaningful notes, completed provenance decision, all
eleven checks, and a fresh similarity pass. It creates
`<pack_id>.validated.json`; it never overwrites the draft file.

## 6. Publish Explicitly

Validation and publication are deliberately separate actions:

```bash
dart run tool/question_bank.dart promote <pack_id> \
  --to published \
  --publisher <publisher_id>
```

Only a validated pack can be published. The command records publisher identity
and UTC publication time, creates `<pack_id>.published.json`, preserves the
validated artifact, and updates the manifest to the published artifact.

Inspect the final state:

```bash
dart run tool/question_bank.dart list
dart run tool/question_bank.dart validate \
  assets/question_bank/<pack_id>.published.json
```

## 7. Load and Verify on Device

```bash
flutter test
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

On startup, SQLite schema v6 imports a new reviewed pack or advances an existing
matching pack's lifecycle transactionally. It stores reviewer, review time,
notes, provenance decision/notes, digest, checklist evidence, publisher, and
publication time. If content under an existing ID differs, startup fails closed
instead of modifying historical question meaning.

## Correction Policy

- Never edit or delete an accepted lifecycle artifact.
- Never change question content, answer, taxonomy, or explanation under an
  existing question ID.
- Corrections require an incremented pack/content version and new pack/question
  IDs.
- Retain the old artifact for sessions and audit history.
- Only activate or publish the corrected version after a complete new review.

## Current Repository State

The bank manifest currently contains no imported AI pack. The built-in TIU
prototype remains development-only `draft` content. This tooling intentionally
does not manufacture a human approval or publish a pack automatically.
