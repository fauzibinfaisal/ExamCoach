# ExamCoach — Release Versioning

## Current Version

The current development build is `0.11.0+11`.

- `0.11.0` is the public application version (`build-name`).
- `11` is the monotonically increasing store/build number (`build-number`).
- Major version zero communicates that ExamCoach is still in initial
  development and its public behavior may change before the first stable
  release.

The database schema is independently versioned and is currently schema v8. App
version and database schema version must never be assumed to advance together.

## Policy Before 1.0

Use `0.MINOR.PATCH+BUILD`:

- increment `MINOR` for a completed roadmap capability or a breaking
  development contract;
- increment `PATCH` for compatible fixes and small refinements within the same
  milestone;
- increment `BUILD` for every distributable Android or iOS build; and
- reserve `1.0.0` for the first owner-approved, production-ready release.

Examples:

| Change | Next version example |
|---|---|
| Step 8 milestone build | `0.8.0+8` |
| Step 9 milestone build | `0.9.0+9` |
| Step 9 corrective build | `0.9.1+10` |
| Step 10 milestone build | `0.10.0+10` |
| Step 11 milestone build | `0.11.0+11` |
| First production release | `1.0.0+N` |

The three-part numeric version is kept platform-safe for Flutter, Android, and
iOS. Development stage, branch, commit, and build channel belong in Git/CI
metadata rather than a hyphenated `pubspec.yaml` version.

## Git Flow and Tags

- Feature and bugfix work changes version metadata on its own short-lived branch
  when it produces a new distributable build.
- Active development merges into `develop`; it is not tagged as a production
  release.
- A production candidate is stabilized in `release/x.y.z`.
- After owner approval and merge to `main`, create the annotated tag `vX.Y.Z`.
- Hotfixes increment the released patch version and are merged back into
  `develop`.

## Release Checklist

Before tagging a release:

1. Update `pubspec.yaml`, release notes, and project status together.
2. Confirm Android `versionName`/`versionCode` and iOS
   `CFBundleShortVersionString`/`CFBundleVersion` in built artifacts.
3. Run formatting, static analysis, the full test suite, and both mobile build
   smoke checks.
4. Confirm database migrations from every supported installed schema.
5. Merge through the protected release flow only after owner testing and
   approval.
6. Tag the exact released `main` commit; never move or reuse a release tag.

## References

- Semantic Versioning: <https://semver.org/>
- Flutter iOS deployment and version metadata:
  <https://docs.flutter.dev/deployment/ios>
