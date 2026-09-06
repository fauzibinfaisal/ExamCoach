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
```

Use Conventional Commit subjects such as `feat:`, `fix:`, `test:`, `docs:`,
`refactor:`, `build:`, and `chore:`. Keep each pull request focused, update the
handoff documents when the project state changes, and never promote draft
question content without the documented human review.

Before creating a distributable build, increment the integer build number. Use
`0.MINOR.PATCH+BUILD` during initial development and reserve `1.0.0` for the
first owner-approved production release.
