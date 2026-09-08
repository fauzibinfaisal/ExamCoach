# Contributing to ExamCoach

ExamCoach uses the Git Flow branching model. Read
[`docs/engineering/Git_Workflow.md`](docs/engineering/Git_Workflow.md) before
starting implementation. Version changes follow
[`docs/engineering/Release_Versioning.md`](docs/engineering/Release_Versioning.md).

## Quick Start

Update the integration branch and create a focused feature branch:

```bash
git switch develop
git pull --ff-only origin develop
git switch -c feature/short-description
```

Before opening a pull request into `develop`, run:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
npm --prefix functions test
```

Use Conventional Commit subjects such as `feat:`, `fix:`, `test:`, `docs:`,
`refactor:`, `build:`, and `chore:`. Keep each pull request focused, update the
handoff documents when the project state changes, and never promote draft
question content without the documented human review.

Before creating a distributable build, increment the integer build number. Use
`0.MINOR.PATCH+BUILD` during initial development and reserve `1.0.0` for the
first owner-approved production release.

Question-pack promotion must follow
[`docs/operations/Human_Question_Review_Workflow.md`](docs/operations/Human_Question_Review_Workflow.md).
Never fill a human review record with AI, overwrite a lifecycle artifact, or
change accepted content under an existing ID.

Firebase work must follow
[`docs/engineering/Firebase_Integration.md`](docs/engineering/Firebase_Integration.md).
Never commit service-account credentials or silently point development commands
at production. User-learning writes must remain behind authenticated callable
Functions rather than direct Firestore client writes.
