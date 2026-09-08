"use strict";

const crypto = require("node:crypto");

const SESSION_STATUSES = new Set([
  "active",
  "completed",
  "cancelled",
  "expired",
]);
const SESSION_MODES = new Set(["tryout", "adaptiveDrill"]);
const TERMINAL_STATUSES = new Set(["completed", "cancelled", "expired"]);

class ProtocolError extends Error {
  constructor(message) {
    super(message);
    this.name = "ProtocolError";
  }
}

function normalizeOperation(source, expectedUid) {
  const value = object(source, "operation");
  const operationId = safeId(value.operationId, "operationId");
  const entityType = string(value.entityType, "entityType");
  const entityId = safeId(value.entityId, "entityId");
  const operation = string(value.operation, "operation");
  const payload = object(value.payload, "payload");
  const createdAt = utcTime(value.createdAt, "createdAt");
  const payloadSize = Buffer.byteLength(JSON.stringify(payload), "utf8");
  if (payloadSize > 100000) {
    throw new ProtocolError("payload exceeds 100 KB");
  }
  if (!new Set(["exam_session", "user_answer", "analytics_event"]).has(entityType)) {
    throw new ProtocolError(`unsupported entityType ${entityType}`);
  }
  const normalized = {
    operationId,
    entityType,
    entityId,
    operation,
    payload,
    createdAt,
    createdAtMs: Date.parse(createdAt),
  };
  if (entityType === "exam_session") {
    normalized.entity = normalizeSession(payload, expectedUid, entityId, operation);
  } else if (entityType === "user_answer") {
    normalized.entity = normalizeAnswer(payload, entityId, operation);
  } else {
    normalized.entity = normalizeAnalytics(payload, expectedUid, entityId, operation);
  }
  const expectedOperationId = stableOperationId(normalized);
  if (operationId !== expectedOperationId) {
    throw new ProtocolError(
      `operationId must be the stable identifier ${expectedOperationId}`,
    );
  }
  normalized.payloadHash = hashPayload({
    entityType,
    entityId,
    operation,
    payload,
  });
  return normalized;
}

function stableOperationId(operation) {
  if (operation.entityType === "exam_session") {
    const suffix = operation.operation === "upsert"
      ? "start"
      : operation.operation;
    return `${operation.entityId}:${suffix}`;
  }
  if (operation.entityType === "user_answer") {
    return `${operation.entity.session_id}:answer:${operation.entity.question_id}`;
  }
  return `analytics:${operation.entityId}`;
}

function normalizeSession(payload, expectedUid, entityId, operation) {
  const id = safeId(payload.id, "payload.id");
  if (id !== entityId || string(payload.user_id, "payload.user_id") !== expectedUid) {
    throw new ProtocolError("session ID or authenticated owner mismatch");
  }
  const status = string(payload.status, "payload.status");
  const expectedStatus = {
    upsert: "active",
    progress: "active",
    complete: "completed",
    cancelled: "cancelled",
    expired: "expired",
  }[operation];
  if (!expectedStatus || status !== expectedStatus || !SESSION_STATUSES.has(status)) {
    throw new ProtocolError("session operation and status do not match");
  }
  const mode = string(payload.mode, "payload.mode");
  if (!SESSION_MODES.has(mode)) throw new ProtocolError("unsupported session mode");
  const questionIds = parseQuestionIds(payload.question_ids_json);
  const currentIndex = integer(payload.current_index, "payload.current_index");
  const syncVersion = integer(payload.sync_version, "payload.sync_version");
  const startedAt = utcTime(payload.started_at, "payload.started_at");
  const updatedAt = utcTime(payload.updated_at, "payload.updated_at");
  const endedAt = nullableUtcTime(payload.ended_at, "payload.ended_at");
  if (questionIds.length === 0 || new Set(questionIds).size !== questionIds.length) {
    throw new ProtocolError("question IDs must be non-empty and unique");
  }
  if (currentIndex < 0 || currentIndex > questionIds.length || syncVersion < 1) {
    throw new ProtocolError("session cursor or sync version is invalid");
  }
  if (Date.parse(updatedAt) < Date.parse(startedAt)) {
    throw new ProtocolError("session updatedAt predates startedAt");
  }
  if (status === "active" && endedAt !== null) {
    throw new ProtocolError("active session cannot have endedAt");
  }
  if (TERMINAL_STATUSES.has(status) && endedAt === null) {
    throw new ProtocolError("terminal session requires endedAt");
  }
  if (endedAt !== null &&
      (Date.parse(endedAt) < Date.parse(startedAt) ||
       Date.parse(endedAt) < Date.parse(updatedAt))) {
    throw new ProtocolError("session endedAt predates its lifecycle timestamps");
  }
  const score = payload.score === null || payload.score === undefined
    ? null
    : integer(payload.score, "payload.score");
  if (score !== null && (score < 0 || score > 100 || status !== "completed")) {
    throw new ProtocolError("score is only valid for a completed session");
  }
  return {
    id,
    user_id: expectedUid,
    test_id: safeId(payload.test_id, "payload.test_id"),
    mode,
    status,
    question_ids: questionIds,
    current_index: currentIndex,
    started_at: startedAt,
    updated_at: updatedAt,
    ended_at: endedAt,
    sync_version: syncVersion,
  };
}

function normalizeAnswer(payload, entityId, operation) {
  if (operation !== "upsert") throw new ProtocolError("answer operation must be upsert");
  const sessionId = safeId(payload.session_id, "payload.session_id");
  const questionId = safeId(payload.question_id, "payload.question_id");
  if (`${sessionId}:${questionId}` !== entityId) {
    throw new ProtocolError("answer entity ID mismatch");
  }
  const skipped = booleanFlag(payload.is_skipped, "payload.is_skipped");
  const selected = string(payload.selected_option_id, "payload.selected_option_id", true);
  if (!skipped && selected.length === 0) {
    throw new ProtocolError("non-skipped answer requires selected option");
  }
  const position = integer(payload.position, "payload.position");
  const timeSpent = integer(payload.time_spent_ms, "payload.time_spent_ms");
  const sessionVersion = integer(
    payload.session_sync_version,
    "payload.session_sync_version",
  );
  const sessionIndex = integer(
    payload.session_current_index,
    "payload.session_current_index",
  );
  if (position < 0 || timeSpent < 0 || sessionVersion < 1 || sessionIndex < 0) {
    throw new ProtocolError("answer position, duration, or session revision is invalid");
  }
  const answeredAt = utcTime(payload.answered_at, "payload.answered_at");
  const sessionUpdatedAt = utcTime(
    payload.session_updated_at,
    "payload.session_updated_at",
  );
  if (Date.parse(answeredAt) > Date.parse(sessionUpdatedAt)) {
    throw new ProtocolError("answer timestamp exceeds its session revision");
  }
  return {
    session_id: sessionId,
    question_id: questionId,
    position,
    selected_option_id: skipped ? "" : selected,
    is_skipped: skipped,
    time_spent_ms: timeSpent,
    changed_answer: booleanFlag(payload.changed_answer, "payload.changed_answer"),
    answered_at: answeredAt,
    session_sync_version: sessionVersion,
    session_current_index: sessionIndex,
    session_updated_at: sessionUpdatedAt,
  };
}

function normalizeAnalytics(payload, expectedUid, entityId, operation) {
  if (operation !== "create") throw new ProtocolError("analytics operation must be create");
  if (safeId(payload.id, "payload.id") !== entityId ||
      string(payload.user_id, "payload.user_id") !== expectedUid) {
    throw new ProtocolError("analytics ID or authenticated owner mismatch");
  }
  return {
    id: entityId,
    user_id: expectedUid,
    event_name: safeId(payload.event_name, "payload.event_name"),
    event_version: integer(payload.event_version, "payload.event_version"),
    occurred_at: utcTime(payload.occurred_at, "payload.occurred_at"),
    session_id: payload.session_id == null
      ? null
      : safeId(payload.session_id, "payload.session_id"),
    properties: parseJsonObject(payload.properties_json, "payload.properties_json"),
  };
}

function decideSessionMutation(existing, incoming, operation, activeSessionId) {
  if (!existing) {
    if (operation !== "upsert" || incoming.sync_version !== 1) {
      throw new ProtocolError("a session must begin with version-1 upsert");
    }
    return "accepted";
  }
  if (existing.id !== incoming.id ||
      existing.user_id !== incoming.user_id ||
      existing.test_id !== incoming.test_id ||
      existing.mode !== incoming.mode ||
      existing.started_at !== incoming.started_at ||
      !sameStringArray(existing.question_ids, incoming.question_ids)) {
    throw new ProtocolError("immutable session fields cannot change");
  }
  if (TERMINAL_STATUSES.has(existing.status)) return "superseded";
  if (activeSessionId && activeSessionId !== incoming.id) return "superseded";
  if (incoming.sync_version <= existing.sync_version) return "superseded";
  if (Date.parse(incoming.updated_at) < Date.parse(existing.updated_at)) {
    throw new ProtocolError("session updatedAt cannot move backwards");
  }
  if (operation === "upsert") throw new ProtocolError("existing session cannot restart");
  return "accepted";
}

function sameStringArray(left, right) {
  return Array.isArray(left) &&
    Array.isArray(right) &&
    left.length === right.length &&
    left.every((value, index) => value === right[index]);
}

function hashPayload(value) {
  return crypto.createHash("sha256").update(canonicalJson(value)).digest("hex");
}

function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function parseQuestionIds(value) {
  let decoded;
  try {
    decoded = typeof value === "string" ? JSON.parse(value) : value;
  } catch (_) {
    throw new ProtocolError("payload.question_ids_json must be valid JSON");
  }
  if (!Array.isArray(decoded)) throw new ProtocolError("question IDs must be an array");
  return decoded.map((item) => safeId(item, "question ID"));
}

function parseJsonObject(value, path) {
  let decoded;
  try {
    decoded = typeof value === "string" ? JSON.parse(value) : value;
  } catch (_) {
    throw new ProtocolError(`${path} must be valid JSON`);
  }
  return object(decoded, path);
}

function object(value, path) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ProtocolError(`${path} must be an object`);
  }
  return value;
}

function string(value, path, allowEmpty = false) {
  if (typeof value !== "string" || (!allowEmpty && value.trim().length === 0)) {
    throw new ProtocolError(`${path} must be a string`);
  }
  return value;
}

function safeId(value, path) {
  const result = string(value, path);
  if (result.length > 240 || result.includes("/")) {
    throw new ProtocolError(`${path} is not a safe document identifier`);
  }
  return result;
}

function integer(value, path) {
  if (!Number.isSafeInteger(value)) throw new ProtocolError(`${path} must be an integer`);
  return value;
}

function booleanFlag(value, path) {
  if (value === true || value === 1) return true;
  if (value === false || value === 0) return false;
  throw new ProtocolError(`${path} must be a boolean flag`);
}

function utcTime(value, path) {
  const result = string(value, path);
  if (!result.endsWith("Z") || !Number.isFinite(Date.parse(result))) {
    throw new ProtocolError(`${path} must be an ISO-8601 UTC timestamp`);
  }
  return new Date(result).toISOString();
}

function nullableUtcTime(value, path) {
  return value == null ? null : utcTime(value, path);
}

module.exports = {
  ProtocolError,
  TERMINAL_STATUSES,
  canonicalJson,
  decideSessionMutation,
  hashPayload,
  normalizeOperation,
};
