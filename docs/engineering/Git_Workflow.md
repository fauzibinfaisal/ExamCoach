# ExamCoach Git Workflow

## Purpose

This repository uses Git Flow to separate released code from active integration
work. The model is intentionally explicit so mobile releases, urgent fixes, and
parallel feature development remain traceable.

## Long-Lived Branches

### `main`

- Contains production-ready, released code only.
- Receives changes from `release/*` and `hotfix/*` pull requests.
- Every release merge is tagged with semantic versioning, for example `v1.2.0`.
- Direct feature development, force pushes, and branch deletion are prohibited.

### `develop`

- Is the integration branch and default base for ongoing product development.
- Receives completed `feature/*` and `bugfix/*` pull requests.
- Must remain buildable and pass the repository validation suite.
- Direct pushes should be limited to repository administration or documentation
  bootstrap work; normal implementation goes through a short-lived branch.

## Short-Lived Branches

| Prefix | Create from | Merge into | Purpose |
| --- | --- | --- | --- |
| `feature/*` | `develop` | `develop` | New product or engineering capability |
| `bugfix/*` | `develop` | `develop` | Non-urgent correction for unreleased code |
| `release/*` | `develop` | `main`, then back to `develop` | Release stabilization and version metadata |
| `hotfix/*` | `main` | `main` and `develop` | Urgent correction to released code |
| `support/*` | Appropriate release tag | As explicitly planned | Exceptional maintenance of an older release |

Use lowercase kebab-case after the prefix, for example
`feature/session-cancellation` or `hotfix/database-migration`.

## Feature Flow

```bash
git switch develop
git pull --ff-only origin develop
git switch -c feature/session-cancellation
# implement, validate, and commit
git push -u origin feature/session-cancellation
```

Open a pull request into `develop`. Delete the feature branch after merge.

## Release Flow

1. Create `release/x.y.z` from the validated `develop` head.
2. Allow only release stabilization, documentation, and version changes.
3. Open a pull request into `main` and run the full release validation suite.
4. Merge the release, create the annotated tag `vX.Y.Z`, and publish from that
   tag.
5. Merge the release changes back into `develop` so version and stabilization
   fixes are retained.

## Hotfix Flow

1. Create `hotfix/x.y.z` from the affected `main` release.
2. Apply the smallest safe fix and validate it.
3. Merge it into `main`, tag the new patch release, and publish.
4. Merge the same fix into `develop`; also merge it into an open `release/*`
   branch when applicable.

## Pull Request Rules

- Target `develop` for normal work; target `main` only for releases and hotfixes.
- Use Conventional Commit subjects and a pull request title that describes one
  cohesive change.
- Complete the repository pull request template.
- Resolve review threads and keep documentation, migrations, and tests aligned
  with the implementation.
- Do not rewrite shared branch history or force-push `main` or `develop`.

At minimum, normal pull requests must pass formatting, `flutter analyze`, and
`flutter test`. Release pull requests must also pass Android and unsigned iOS
build validation.

## GitHub Enforcement

Both `main` and `develop` require pull requests and resolved review
conversations. Force pushes and branch deletion are disabled, including for
repository administrators. The approval count is temporarily zero because the
repository currently has a single owner; increase it to at least one when a
second reviewer is available. Required status checks must be enabled as soon as
the CI workflow supplies stable check names.
