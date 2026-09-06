# ExamCoach — Session Controls and Review

## Objective

Make tryout and adaptive-drill sessions safe to interrupt and easy to inspect
without changing the deterministic scoring boundary.

## User Flow

```text
Active question
  → answer or skip
  → move backward or continue
  → all questions have a response
  → pre-submit review
      → edit any response, or
      → explicitly finish
  → deterministic score and insight
  → post-result answer and explanation review
```

A response is either a selected option or an explicit skip. A result is never
calculated merely because the final question was reached; the user must confirm
completion from the pre-submit review screen.

## Behavior

### Skip and answer changes

- `AnswerRecord.selectedOptionId` is nullable; `null` means explicitly skipped.
- A skipped question is included in the session total and scores as incorrect.
- Returning to a question preselects its saved option, if any.
- Saving a different option, changing an answer to skipped, or answering a
  previously skipped question sets the sticky `changedAnswer` flag.
- Repeated edits accumulate time spent instead of replacing earlier time.
- All response mutations use the same stable answer outbox operation ID, so the
  newest unsynced payload replaces the older pending payload.

### Pre-submit review

- The review shows every question as answered or skipped.
- Any question can be reopened and edited.
- Scoring starts only after `Selesaikan & lihat hasil` is selected.
- An interrupted review is restored directly to the review screen after app or
  database restart.

### Cancellation

- Close and system-back actions require explicit confirmation.
- A cancelled session is retained for audit/sync but is excluded from completed
  answer history, weakness analysis, and recommendations.
- Previously completed learning history remains unchanged.

### Expiry

- An active session expires during bootstrap when its last `updatedAt` is more
  than 24 hours old.
- An expired session is retained with an end timestamp and queued status change.
- Partial answers from an expired session are not included in learning history.
- The user returns to Home with an explanatory message and can start a new
  session.

### Post-result review

- The result page links to a question-by-question review.
- Each card shows the user's answer, correct answer, correctness state, and
  explanation.
- Explanation access is checked through `QuestionReviewAccessPolicy`. The
  development policy currently allows all explanations; future subscription
  work can replace the policy without changing scoring or stored answers.

## State Model

```text
idle
  → answering
      → reviewing
          → answering  (edit)
          → result     (explicit completion)
      → idle           (cancel)

restored active session
  → answering          (pending question)
  → reviewing          (all responses saved)
  → idle               (expired)
```

## Persistence

SQLite schema v4 adds `user_answers.is_skipped`. The existing
`selected_option_id` remains non-null at the SQL boundary for migration
compatibility; skipped rows store an empty value plus `is_skipped = 1`, which is
decoded back to a nullable domain value.

New or updated outbox operation IDs are:

```text
<sessionId>:answer:<questionId>   latest response payload, replace pending
<sessionId>:progress              latest review/edit cursor, replace pending
<sessionId>:cancelled             terminal cancelled status
<sessionId>:expired               terminal expired status
```

Answer writes still atomically update the session cursor/version and response
row. Cursor movement, cancellation, expiry, and completion each persist their
own session version before the UI proceeds.

## Analytics

- `question_skipped`
- `answer_changed`
- `practice_cancelled`
- `practice_expired`
- `question_review_viewed`

Analytics remains best-effort and cannot block response persistence, scoring,
or navigation.

## Manual Test Guide

1. Install the latest debug APK and start `Diagnostic TIU`.
2. Close from the overview, verify the confirmation dialog, then choose
   `Lanjut mengerjakan` and confirm the session remains open.
3. Begin answering, use `Lewati` on one question, and use `Sebelumnya` to revisit
   a saved answer.
4. Finish responding to all six questions and verify the review reports the
   answered/skipped totals.
5. Open the skipped question, choose an option, save it, and verify the review
   count changes.
6. Force-close the app while on a question or the review page, reopen it, and
   use the Home resume card. Verify the exact question/review state is restored.
7. Select `Selesaikan & lihat hasil`; verify the result appears only now.
8. Select `Review jawaban`; verify user answer, correct answer, status, and
   explanation appear for all six questions.
9. Start a drill, cancel it after one response, and verify the previous result
   remains visible while the partial drill is not added to insight history.

The 24-hour expiry boundary is covered by an injected-clock SQLite integration
test. Changing a device clock is not required for normal manual QA.

## Automated Validation

- Cubit tests cover review-gated completion, skip, answer change, analytics, and
  cancellation.
- SQLite integration tests cover schema v1→v4 migration, interrupted question
  recovery, review recovery, expiry, cancellation, history isolation, and
  outbox state.
- Widget tests cover cancellation confirmation and the complete
  skip→edit→review→result→explanation→drill journey.

## Deferred

- Server-authoritative entitlement policy for detailed explanations.
- Cross-device active-session conflict resolution.
- Remote status acknowledgement, retry backoff, and dead-letter handling.
- Configurable expiry duration from remote product configuration.
