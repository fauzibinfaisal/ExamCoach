# ExamCoach — Firebase Authentication and Recovery

## Status and Scope

Step 10 implements the application and backend code for optional Firebase
email/password authentication, authenticated outbox upload, and safe
cross-device recovery. The repository does **not** contain a Firebase project,
service-account credential, or production deployment. Without explicit runtime
configuration the app fails closed to local-only mode and the complete learning
loop remains usable offline.

Implemented components:

- Firebase Auth adapter and account UI for registration, sign-in, password
  reset, and sign-out;
- authenticated callable `pushSyncBatch` and `pullRecoverySnapshot` gateways;
- Cloud Functions on Node 22 with ownership, payload, lifecycle, stable
  idempotency-key, and revision validation;
- Firestore Rules that permit an owner to read their records while denying all
  direct mobile writes to user learning data;
- SQLite schema v7 single-owner account binding;
- atomic migration of `local_user` session, analytics, and outbox ownership at
  first sign-in;
- empty-device recovery with local question/answer validation and local score
  recomputation; and
- Auth, Functions, and Firestore emulator declarations.

The implementation intentionally does not perform a live two-way merge. A
device that already has any session keeps its local state and uploads the
outbox. A device with no local sessions may import the authenticated account's
remote snapshot. This prevents an inbound response from silently overwriting
deterministic local learning evidence.

## Owner Setup

1. Create separate Firebase projects for development and production. Start with
   development only.
2. Register Android package `id.examcoach.exam_coach` and iOS bundle
   `id.examcoach.examCoach`. These identifiers are provisional until the owner
   confirms release identifiers.
3. Enable Email/Password under Firebase Authentication → Sign-in method.
4. Create Firestore and choose the intended data location. Cloud Functions in
   this repository use `asia-southeast2`; keep the runtime configuration aligned
   if the owner changes that region.
5. Install the Firebase CLI and authenticate it, then install Functions
   dependencies using Node 22:

   ```bash
   npm install -g firebase-tools
   firebase login
   cd functions
   nvm use
   npm install
   cd ..
   ```

6. Deploy only to the explicitly named development project:

   ```bash
   firebase deploy --project YOUR_FIREBASE_PROJECT_ID \
     --only firestore:rules,firestore:indexes,functions
   ```

7. Copy the runtime template and replace every placeholder with values from the
   registered Firebase apps:

   ```bash
   cp config/firebase.dart-defines.example.json config/firebase.dev.json
   ```

   `config/firebase.dev.json` is ignored by Git. Firebase client identifiers are
   configuration rather than server credentials, but keeping environment files
   local prevents accidental development/production mixing. Never put a service
   account private key, Admin SDK JSON, or AI-provider secret in this file or in
   the mobile app.

8. Run the app:

   ```bash
   flutter run --dart-define-from-file=config/firebase.dev.json
   ```

If `EXAMCOACH_FIREBASE_ENABLED` is absent/false or any required value is empty,
the Account screen explains that Firebase is unavailable and the app stays in
local mode instead of starting a partially configured remote client.

## Emulator Setup

Set `EXAMCOACH_FIREBASE_USE_EMULATORS` to `true` in a local copy of the template.
For an Android emulator use host `10.0.2.2`; for iOS Simulator or desktop-hosted
tests use `127.0.0.1`. Then run:

```bash
firebase emulators:start --project demo-examcoach
flutter run --dart-define-from-file=config/firebase.dev.json
```

Declared ports are Auth `9099`, Functions `5001`, Firestore `8080`, and Emulator
UI `4000`. The `demo-` project ID prevents accidental access to a real Firebase
project while testing emulators.

Run backend checks with:

```bash
npm --prefix functions test
firebase emulators:exec --project demo-examcoach --only firestore \
  "npm --prefix functions run test:rules"
firebase emulators:exec --project demo-examcoach \
  --only auth,firestore,functions \
  "npm --prefix functions run test:callable"
```

## Manual Acceptance Test

Use a development Firebase project or the emulator only.

1. Install/open Device A without Firebase configuration and finish one short
   tryout. Confirm local learning still works and Account shows local mode.
2. Relaunch with Firebase enabled, create Account A, and confirm the local data
   claim message appears.
3. Go offline, complete another answer/session action, and confirm the app does
   not block. Reconnect and allow startup/reconnect sync to run.
4. Inspect Firestore under `users/<uid>` and confirm sessions, answers,
   analytics, operation ledger, and monotonically increasing user revision are
   owned by Account A.
5. Retry the same operation or interrupt a response. Confirm the ledger returns
   `duplicate` or `superseded` and the local outbox closes it without changing
   local score/insight.
6. On a clean Device B with the same question-pack build, sign in as Account A.
   Confirm sessions/answers recover and scores/insights are recomputed locally.
7. Create any local session on Device B before sign-in and confirm remote import
   is skipped; local state is retained and uploaded.
8. Sign out. Confirm local data remains. Attempt Account B on the same database
   and confirm it is rejected because explicit local-data reset is not yet
   implemented.
9. In Firestore client code or the Rules test, confirm an unauthenticated user
   and another UID cannot read Account A, and even Account A cannot write user
   learning documents directly.

## Data Layout

```text
users/{uid}
├── revision
├── active_session_id
├── sessions/{sessionId}
│   └── answers/{questionId}
├── operations/{operationId}
└── analytics/{eventId}
```

Every mutation comes through callable Functions. The authenticated UID is the
owner; a payload claiming another `user_id` is rejected. The operation ledger
stores the stable ID, canonical payload hash, client creation time, processing
time, and assigned remote revision. Correct answers and computed correctness are
not accepted from the client; recovery derives them from the installed local
question pack.

## Recovery and Account Safety

- The first successful sign-in permanently binds the existing SQLite database
  to that Firebase UID and atomically rewrites `local_user` ownership.
- Sign-out clears authentication but never clears the database binding or local
  progress.
- Another UID is refused on that database. A reviewed, explicit destructive
  reset/export flow is deferred; silently switching owners is forbidden.
- Recovery accepts at most 200 sessions, 500 answers per session, and 5,000
  answers total; it verifies stable IDs,
  UID ownership, timestamps, lifecycle, single-active-session state, question
  membership, option IDs, and installed content availability.
- Completed sessions must contain every response. Score and correctness are
  recomputed locally and remote values are not trusted.
- Existing local sessions always win over an inbound snapshot in Step 10.

## Known Limitations

- The owner must create/configure/deploy a real Firebase project before remote
  behavior can be tested against production infrastructure.
- No explicit local-data export/reset/account-switch workflow exists yet.
- Recovery is an empty-device restore, not general multi-writer reconciliation.
- A transient recovery-download failure is attempted again on the next app
  launch or authentication-state event; there is no dedicated manual re-pull
  action yet.
- Sync runs at app startup and connectivity changes; OS-scheduled background
  delivery and operator dead-letter re-drive remain future work.
- App Check, provider sign-in, email verification policy, observability, backup
  policy, and retention/deletion controls remain release-readiness work.
- The current development machine uses Node 26, while deployed Functions are
  pinned to Node 22 via `functions/package.json` and `.nvmrc`.
- `firebase-admin` currently brings older `uuid` transitively through its
  unused Storage client. `functions/package.json` overrides it to patched
  `11.1.1`; keep the lockfile and re-run `npm audit` when Firebase packages
  change.

## References

- Firebase Flutter setup: <https://firebase.google.com/docs/flutter/setup>
- Firebase Auth email/password for Flutter:
  <https://firebase.google.com/docs/auth/flutter/password-auth>
- Callable Functions authentication context:
  <https://firebase.google.com/docs/functions/callable>
- Firestore Rules conditions:
  <https://firebase.google.com/docs/firestore/security/rules-conditions>
- Firestore Rules emulator testing:
  <https://firebase.google.com/docs/rules/emulator-setup>
- Cloud Functions runtime support:
  <https://firebase.google.com/docs/functions/manage-functions#set_nodejs_version>
