"use strict";

const {initializeApp} = require("firebase-admin/app");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");
const {HttpsError, onCall} = require("firebase-functions/v2/https");
const {
  ProtocolError,
  TERMINAL_STATUSES,
  decideSessionMutation,
  normalizeOperation,
} = require("./sync_core");

initializeApp();
const db = getFirestore();
const REGION = "asia-southeast2";

exports.pushSyncBatch = onCall(
  {region: REGION, timeoutSeconds: 60, memory: "256MiB"},
  async (request) => {
    const uid = requireUid(request);
    const data = requireProtocol(request.data);
    if (!Array.isArray(data.operations) ||
        data.operations.length < 1 ||
        data.operations.length > 25) {
      throw new HttpsError(
        "invalid-argument",
        "operations must contain between 1 and 25 items",
      );
    }
    const operationIds = new Set();
    const results = [];
    for (const source of data.operations) {
      let operation;
      try {
        operation = normalizeOperation(source, uid);
        if (operationIds.has(operation.operationId)) {
          throw new ProtocolError("batch contains duplicate operationId");
        }
        operationIds.add(operation.operationId);
        results.push(await applyOperation(uid, operation));
      } catch (error) {
        if (error instanceof ProtocolError) {
          results.push({
            operationId: operation?.operationId ?? safeResultId(source),
            outcome: "rejected",
            message: error.message,
          });
          continue;
        }
        throw error;
      }
    }
    return {protocolVersion: 1, results};
  },
);

exports.pullRecoverySnapshot = onCall(
  {region: REGION, timeoutSeconds: 60, memory: "256MiB"},
  async (request) => {
    const uid = requireUid(request);
    requireProtocol(request.data);
    const userRef = db.collection("users").doc(uid);
    const [userSnapshot, sessionSnapshot] = await Promise.all([
      userRef.get(),
      userRef.collection("sessions").orderBy("updated_at", "asc").limit(201).get(),
    ]);
    if (sessionSnapshot.size > 200) {
      throw new HttpsError(
        "resource-exhausted",
        "recovery snapshot exceeds 200 sessions",
      );
    }
    const sessions = [];
    const answers = [];
    for (const document of sessionSnapshot.docs) {
      const session = document.data();
      sessions.push(publicSession(session));
      const answerSnapshot = await document.ref
        .collection("answers")
        .orderBy("position", "asc")
        .limit(501)
        .get();
      if (answerSnapshot.size > 500) {
        throw new HttpsError(
          "resource-exhausted",
          `session ${document.id} exceeds 500 answers`,
        );
      }
      for (const answerDocument of answerSnapshot.docs) {
        answers.push(publicAnswer(answerDocument.data()));
        if (answers.length > 5000) {
          throw new HttpsError(
            "resource-exhausted",
            "recovery snapshot exceeds 5000 answers",
          );
        }
      }
    }
    return {
      protocolVersion: 1,
      userId: uid,
      remoteRevision: userSnapshot.exists
        ? integerOrZero(userSnapshot.data().revision)
        : 0,
      sessions,
      answers,
    };
  },
);

async function applyOperation(uid, operation) {
  const userRef = db.collection("users").doc(uid);
  const ledgerRef = userRef.collection("operations").doc(operation.operationId);
  return db.runTransaction(async (transaction) => {
    const userSnapshot = await transaction.get(userRef);
    const ledgerSnapshot = await transaction.get(ledgerRef);
    const user = userSnapshot.exists ? userSnapshot.data() : {};
    if (ledgerSnapshot.exists) {
      const ledger = ledgerSnapshot.data();
      if (ledger.payload_hash === operation.payloadHash) {
        return result(operation, "duplicate", integerOrZero(ledger.remote_revision));
      }
      if (Date.parse(ledger.created_at) >= operation.createdAtMs) {
        return result(operation, "superseded", integerOrZero(ledger.remote_revision));
      }
    }

    const currentRevision = integerOrZero(user.revision);
    const nextRevision = currentRevision + 1;
    let outcome;
    if (operation.entityType === "exam_session") {
      outcome = await applySession(
        transaction,
        userRef,
        user,
        operation,
        nextRevision,
      );
    } else if (operation.entityType === "user_answer") {
      outcome = await applyAnswer(
        transaction,
        userRef,
        user,
        operation,
        nextRevision,
      );
    } else {
      outcome = await applyAnalytics(
        transaction,
        userRef,
        operation,
        nextRevision,
      );
    }
    if (outcome !== "accepted") {
      return result(operation, outcome, currentRevision);
    }

    transaction.set(
      userRef,
      {
        uid,
        revision: nextRevision,
        updated_at: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    transaction.set(ledgerRef, {
      operation_id: operation.operationId,
      entity_type: operation.entityType,
      entity_id: operation.entityId,
      operation: operation.operation,
      payload_hash: operation.payloadHash,
      created_at: operation.createdAt,
      remote_revision: nextRevision,
      processed_at: FieldValue.serverTimestamp(),
    });
    return result(operation, "accepted", nextRevision);
  });
}

async function applySession(
  transaction,
  userRef,
  user,
  operation,
  nextRevision,
) {
  const session = operation.entity;
  const sessionRef = userRef.collection("sessions").doc(session.id);
  const sessionSnapshot = await transaction.get(sessionRef);
  const existing = sessionSnapshot.exists ? sessionSnapshot.data() : null;
  const activeSessionId = typeof user.active_session_id === "string"
    ? user.active_session_id
    : null;
  const decision = decideSessionMutation(
    existing,
    session,
    operation.operation,
    activeSessionId,
  );
  if (decision !== "accepted") return decision;

  if (operation.operation === "complete") {
    const answerSnapshot = await transaction.get(
      sessionRef.collection("answers").limit(session.question_ids.length + 1),
    );
    const answeredQuestionIds = new Set(
      answerSnapshot.docs.map((document) => document.data().question_id),
    );
    if (answerSnapshot.size !== session.question_ids.length ||
        session.question_ids.some((questionId) =>
          !answeredQuestionIds.has(questionId))) {
      throw new ProtocolError("completed session requires every answer");
    }
  }

  let previousActive = null;
  if (operation.operation === "upsert" &&
      activeSessionId &&
      activeSessionId !== session.id) {
    const previousRef = userRef.collection("sessions").doc(activeSessionId);
    const previousSnapshot = await transaction.get(previousRef);
    if (previousSnapshot.exists && previousSnapshot.data().status === "active") {
      previousActive = {ref: previousRef, data: previousSnapshot.data()};
    }
  }
  if (previousActive) {
    transaction.update(previousActive.ref, {
      status: "cancelled",
      ended_at: session.started_at,
      updated_at: session.started_at,
      sync_version: integerOrZero(previousActive.data.sync_version) + 1,
      remote_revision: nextRevision,
      superseded_by_session_id: session.id,
      server_updated_at: FieldValue.serverTimestamp(),
    });
  }
  transaction.set(sessionRef, {
    ...session,
    remote_revision: nextRevision,
    server_updated_at: FieldValue.serverTimestamp(),
  });
  if (session.status === "active") {
    transaction.set(userRef, {active_session_id: session.id}, {merge: true});
  } else if (activeSessionId === session.id) {
    transaction.set(userRef, {active_session_id: null}, {merge: true});
  }
  return "accepted";
}

async function applyAnswer(
  transaction,
  userRef,
  user,
  operation,
  nextRevision,
) {
  const answer = operation.entity;
  const sessionRef = userRef.collection("sessions").doc(answer.session_id);
  const answerRef = sessionRef.collection("answers").doc(answer.question_id);
  const sessionSnapshot = await transaction.get(sessionRef);
  if (!sessionSnapshot.exists) throw new ProtocolError("answer session does not exist");
  const session = sessionSnapshot.data();
  if (session.status === "active" &&
      user.active_session_id &&
      user.active_session_id !== answer.session_id) {
    return "superseded";
  }
  if (!Array.isArray(session.question_ids) ||
      session.question_ids[answer.position] !== answer.question_id ||
      answer.session_current_index > session.question_ids.length) {
    throw new ProtocolError("answer question/position is not in the session");
  }
  if (Date.parse(answer.answered_at) < Date.parse(session.started_at) ||
      Date.parse(answer.session_updated_at) < Date.parse(session.started_at)) {
    throw new ProtocolError("answer predates the session");
  }
  if (TERMINAL_STATUSES.has(session.status) &&
      session.ended_at &&
      Date.parse(answer.answered_at) > Date.parse(session.ended_at)) {
    throw new ProtocolError("answer was recorded after session end");
  }
  if (TERMINAL_STATUSES.has(session.status)) {
    return "superseded";
  }
  if (answer.session_sync_version <= integerOrZero(session.sync_version) &&
      Date.parse(answer.session_updated_at) > Date.parse(session.updated_at)) {
    throw new ProtocolError("answer metadata does not advance the session revision");
  }
  const answerSnapshot = await transaction.get(answerRef);
  if (answerSnapshot.exists &&
      Date.parse(answerSnapshot.data().answered_at) >= Date.parse(answer.answered_at)) {
    return "superseded";
  }
  transaction.set(answerRef, {
    session_id: answer.session_id,
    question_id: answer.question_id,
    position: answer.position,
    selected_option_id: answer.selected_option_id,
    is_skipped: answer.is_skipped,
    time_spent_ms: answer.time_spent_ms,
    changed_answer: answer.changed_answer,
    answered_at: answer.answered_at,
    remote_revision: nextRevision,
    server_updated_at: FieldValue.serverTimestamp(),
  });
  if (session.status === "active" &&
      answer.session_sync_version > integerOrZero(session.sync_version)) {
    transaction.update(sessionRef, {
      current_index: Math.min(
        answer.session_current_index,
        session.question_ids.length,
      ),
      updated_at: answer.session_updated_at,
      sync_version: answer.session_sync_version,
      remote_revision: nextRevision,
      server_updated_at: FieldValue.serverTimestamp(),
    });
  }
  return "accepted";
}

async function applyAnalytics(
  transaction,
  userRef,
  operation,
  nextRevision,
) {
  const eventRef = userRef.collection("analytics").doc(operation.entity.id);
  const eventSnapshot = await transaction.get(eventRef);
  if (eventSnapshot.exists) return "superseded";
  transaction.create(eventRef, {
    ...operation.entity,
    remote_revision: nextRevision,
    server_created_at: FieldValue.serverTimestamp(),
  });
  return "accepted";
}

function requireUid(request) {
  const uid = request.auth?.uid;
  if (typeof uid !== "string" || uid.length === 0) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  return uid;
}

function requireProtocol(data) {
  if (!data || data.protocolVersion !== 1) {
    throw new HttpsError("invalid-argument", "protocolVersion must be 1");
  }
  return data;
}

function result(operation, outcome, remoteRevision) {
  return {
    operationId: operation.operationId,
    outcome,
    remoteRevision,
  };
}

function safeResultId(source) {
  const value = source && typeof source.operationId === "string"
    ? source.operationId
    : "invalid_operation";
  return value.length <= 240 && !value.includes("/")
    ? value
    : "invalid_operation";
}

function integerOrZero(value) {
  return Number.isSafeInteger(value) && value >= 0 ? value : 0;
}

function publicSession(value) {
  return {
    id: value.id,
    test_id: value.test_id,
    mode: value.mode,
    status: value.status,
    question_ids: Array.isArray(value.question_ids) ? value.question_ids : [],
    current_index: value.current_index,
    started_at: value.started_at,
    updated_at: value.updated_at,
    ended_at: value.ended_at ?? null,
    score: null,
    sync_version: value.sync_version,
  };
}

function publicAnswer(value) {
  return {
    session_id: value.session_id,
    question_id: value.question_id,
    position: value.position,
    selected_option_id: value.selected_option_id ?? "",
    is_skipped: value.is_skipped,
    time_spent_ms: value.time_spent_ms,
    changed_answer: value.changed_answer,
    answered_at: value.answered_at,
  };
}
