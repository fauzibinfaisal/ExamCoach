"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const projectId = process.env.GCLOUD_PROJECT || "demo-examcoach";
const functionsHost = process.env.FUNCTIONS_EMULATOR_HOST || "127.0.0.1:5001";
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099";
const functionRoot = `http://${functionsHost}/${projectId}/asia-southeast2`;

test("authenticated callable sync is idempotent and recoverable", async () => {
  const unauthenticated = await callable("pullRecoverySnapshot", {
    protocolVersion: 1,
  });
  assert.equal(unauthenticated.response.status, 401);
  assert.equal(unauthenticated.body.error.status, "UNAUTHENTICATED");

  const account = await createAccount();
  const startedAt = "2026-09-07T08:00:00.000Z";
  const startOperation = {
    operationId: "session_e2e:start",
    entityType: "exam_session",
    entityId: "session_e2e",
    operation: "upsert",
    createdAt: startedAt,
    payload: {
      id: "session_e2e",
      user_id: account.localId,
      test_id: "test_tiu",
      mode: "tryout",
      status: "active",
      question_ids_json: "[\"q_1\"]",
      current_index: 0,
      started_at: startedAt,
      updated_at: startedAt,
      ended_at: null,
      score: null,
      sync_version: 1,
    },
  };

  let result = await push(account.idToken, startOperation);
  assert.equal(result.outcome, "accepted");
  assert.equal(result.remoteRevision, 1);

  result = await push(account.idToken, startOperation);
  assert.equal(result.outcome, "duplicate");
  assert.equal(result.remoteRevision, 1);

  result = await push(account.idToken, {
    operationId: "session_e2e:answer:q_1",
    entityType: "user_answer",
    entityId: "session_e2e:q_1",
    operation: "upsert",
    createdAt: "2026-09-07T08:01:00.000Z",
    payload: {
      session_id: "session_e2e",
      question_id: "q_1",
      position: 0,
      selected_option_id: "a",
      is_skipped: 0,
      time_spent_ms: 30000,
      changed_answer: 0,
      answered_at: "2026-09-07T08:00:30.000Z",
      session_sync_version: 2,
      session_current_index: 1,
      session_updated_at: "2026-09-07T08:00:30.000Z",
    },
  });
  assert.equal(result.outcome, "accepted");
  assert.equal(result.remoteRevision, 2);

  result = await push(account.idToken, {
    ...startOperation,
    operationId: "session_e2e:complete",
    operation: "complete",
    createdAt: "2026-09-07T08:02:00.000Z",
    payload: {
      ...startOperation.payload,
      status: "completed",
      current_index: 1,
      updated_at: "2026-09-07T08:02:00.000Z",
      ended_at: "2026-09-07T08:02:00.000Z",
      score: 100,
      sync_version: 3,
    },
  });
  assert.equal(result.outcome, "accepted");
  assert.equal(result.remoteRevision, 3);

  result = await push(account.idToken, {
    operationId: "session_e2e:answer:q_1",
    entityType: "user_answer",
    entityId: "session_e2e:q_1",
    operation: "upsert",
    createdAt: "2026-09-07T08:03:00.000Z",
    payload: {
      session_id: "session_e2e",
      question_id: "q_1",
      position: 0,
      selected_option_id: "b",
      is_skipped: 0,
      time_spent_ms: 35000,
      changed_answer: 1,
      answered_at: "2026-09-07T08:01:30.000Z",
      session_sync_version: 4,
      session_current_index: 1,
      session_updated_at: "2026-09-07T08:02:00.000Z",
    },
  });
  assert.equal(result.outcome, "superseded");
  assert.equal(result.remoteRevision, 3);

  const recovery = await callable(
    "pullRecoverySnapshot",
    {protocolVersion: 1},
    account.idToken,
  );
  assert.equal(recovery.response.status, 200);
  const snapshot = callableResult(recovery.body);
  assert.equal(snapshot.userId, account.localId);
  assert.equal(snapshot.remoteRevision, 3);
  assert.equal(snapshot.sessions.length, 1);
  assert.equal(snapshot.sessions[0].score, null);
  assert.equal(snapshot.answers.length, 1);
  assert.equal(snapshot.answers[0].question_id, "q_1");
  assert.equal(snapshot.answers[0].selected_option_id, "a");

  const incompleteStart = {
    ...startOperation,
    operationId: "session_incomplete:start",
    entityId: "session_incomplete",
    createdAt: "2026-09-07T09:00:00.000Z",
    payload: {
      ...startOperation.payload,
      id: "session_incomplete",
      question_ids_json: "[\"q_2\"]",
      started_at: "2026-09-07T09:00:00.000Z",
      updated_at: "2026-09-07T09:00:00.000Z",
    },
  };
  result = await push(account.idToken, incompleteStart);
  assert.equal(result.outcome, "accepted");

  result = await push(account.idToken, {
    ...incompleteStart,
    operationId: "session_incomplete:complete",
    operation: "complete",
    createdAt: "2026-09-07T09:01:00.000Z",
    payload: {
      ...incompleteStart.payload,
      status: "completed",
      current_index: 1,
      updated_at: "2026-09-07T09:01:00.000Z",
      ended_at: "2026-09-07T09:01:00.000Z",
      score: 100,
      sync_version: 2,
    },
  });
  assert.equal(result.outcome, "rejected");
  assert.match(result.message, /requires every answer/);
});

async function createAccount() {
  const response = await fetch(
    `http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: `sync-${Date.now()}@example.com`,
        password: "test-password-123",
        returnSecureToken: true,
      }),
    },
  );
  const body = await response.json();
  assert.equal(response.status, 200, JSON.stringify(body));
  assert.equal(typeof body.idToken, "string");
  assert.equal(typeof body.localId, "string");
  return body;
}

async function push(idToken, operation) {
  const call = await callable(
    "pushSyncBatch",
    {protocolVersion: 1, operations: [operation]},
    idToken,
  );
  assert.equal(call.response.status, 200, JSON.stringify(call.body));
  const result = callableResult(call.body);
  assert.equal(result.protocolVersion, 1);
  assert.equal(result.results.length, 1);
  return result.results[0];
}

async function callable(name, data, idToken) {
  const headers = {"content-type": "application/json"};
  if (idToken) headers.authorization = `Bearer ${idToken}`;
  const response = await fetch(`${functionRoot}/${name}`, {
    method: "POST",
    headers,
    body: JSON.stringify({data}),
  });
  return {response, body: await response.json()};
}

function callableResult(body) {
  return body.result ?? body.data;
}
