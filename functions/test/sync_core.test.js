"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  ProtocolError,
  canonicalJson,
  decideSessionMutation,
  hashPayload,
  normalizeOperation,
} = require("../sync_core");

const uid = "firebase_user_123";

test("normalizes an owned version-1 session start", () => {
  const operation = normalizeOperation(sessionOperation(), uid);
  assert.equal(operation.entity.user_id, uid);
  assert.deepEqual(operation.entity.question_ids, ["q_1", "q_2"]);
  assert.equal(operation.entity.sync_version, 1);
});

test("rejects a forged owner", () => {
  const source = sessionOperation();
  source.payload.user_id = "other_user";
  assert.throws(() => normalizeOperation(source, uid), ProtocolError);
});

test("rejects an operation that bypasses the stable idempotency key", () => {
  const source = sessionOperation();
  source.operationId = "arbitrary_retry_key";
  assert.throws(() => normalizeOperation(source, uid), /stable identifier/);
});

test("rejects invalid lifecycle operation and oversized cursor", () => {
  const source = sessionOperation();
  source.operation = "complete";
  assert.throws(() => normalizeOperation(source, uid), /status do not match/);
  const badCursor = sessionOperation();
  badCursor.payload.current_index = 3;
  assert.throws(() => normalizeOperation(badCursor, uid), /cursor/);
});

test("requires answer session revision metadata", () => {
  const source = answerOperation();
  delete source.payload.session_sync_version;
  assert.throws(() => normalizeOperation(source, uid), /session_sync_version/);
});

test("rejects an answer newer than its session revision", () => {
  const source = answerOperation();
  source.payload.session_updated_at = "2026-09-07T01:00:30.000Z";
  assert.throws(() => normalizeOperation(source, uid), /exceeds its session revision/);
});

test("accepts only a version-1 start and forward active transition", () => {
  const incoming = normalizeOperation(sessionOperation(), uid).entity;
  assert.equal(decideSessionMutation(null, incoming, "upsert", null), "accepted");
  assert.equal(
    decideSessionMutation(
      {...incoming, sync_version: 1},
      {...incoming, sync_version: 2},
      "progress",
      incoming.id,
    ),
    "accepted",
  );
  assert.equal(
    decideSessionMutation(
      {...incoming, status: "completed", sync_version: 3},
      {...incoming, sync_version: 4},
      "progress",
      incoming.id,
    ),
    "superseded",
  );
});

test("rejects changes to immutable session meaning", () => {
  const incoming = normalizeOperation(sessionOperation(), uid).entity;
  assert.throws(
    () => decideSessionMutation(
      {...incoming, sync_version: 1},
      {...incoming, question_ids: ["different_question"], sync_version: 2},
      "progress",
      incoming.id,
    ),
    /immutable session fields/,
  );
});

test("normalization validates but does not trust a reported score", () => {
  const source = sessionOperation();
  source.operationId = "session_1:complete";
  source.operation = "complete";
  source.payload.status = "completed";
  source.payload.current_index = 2;
  source.payload.updated_at = "2026-09-07T01:05:00.000Z";
  source.payload.ended_at = "2026-09-07T01:05:00.000Z";
  source.payload.score = 100;

  const normalized = normalizeOperation(source, uid);
  assert.equal(Object.hasOwn(normalized.entity, "score"), false);
});

test("canonical payload hash is independent of object key order", () => {
  assert.equal(canonicalJson({b: 2, a: 1}), canonicalJson({a: 1, b: 2}));
  assert.equal(hashPayload({b: 2, a: 1}), hashPayload({a: 1, b: 2}));
});

function sessionOperation() {
  return {
    operationId: "session_1:start",
    entityType: "exam_session",
    entityId: "session_1",
    operation: "upsert",
    createdAt: "2026-09-07T01:00:00.000Z",
    payload: {
      id: "session_1",
      user_id: uid,
      test_id: "test_tiu",
      mode: "tryout",
      status: "active",
      question_ids_json: "[\"q_1\",\"q_2\"]",
      current_index: 0,
      started_at: "2026-09-07T01:00:00.000Z",
      updated_at: "2026-09-07T01:00:00.000Z",
      ended_at: null,
      score: null,
      sync_version: 1,
    },
  };
}

function answerOperation() {
  return {
    operationId: "session_1:answer:q_1",
    entityType: "user_answer",
    entityId: "session_1:q_1",
    operation: "upsert",
    createdAt: "2026-09-07T01:01:00.000Z",
    payload: {
      session_id: "session_1",
      question_id: "q_1",
      position: 0,
      selected_option_id: "a",
      is_skipped: 0,
      time_spent_ms: 30000,
      changed_answer: 0,
      answered_at: "2026-09-07T01:01:00.000Z",
      session_sync_version: 2,
      session_current_index: 1,
      session_updated_at: "2026-09-07T01:01:00.000Z",
    },
  };
}
