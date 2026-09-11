"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const test = require("node:test");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {canonicalJson} = require("../sync_core");

const projectId = process.env.GCLOUD_PROJECT || "demo-examcoach";
const functionsHost = process.env.FUNCTIONS_EMULATOR_HOST || "127.0.0.1:5001";
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099";
const functionRoot = `http://${functionsHost}/${projectId}/asia-southeast2`;

test("AI Coach callable enforces auth, cache, quota, and entitlement", async () => {
  const unauthenticated = await callable("getAiCoachStatus", {
    protocolVersion: 1,
  });
  assert.equal(unauthenticated.response.status, 401);

  const adminApp = initializeApp({projectId}, `ai-coach-test-${Date.now()}`);
  const database = getFirestore(adminApp);
  await database.collection("config").doc("ai_coach_policy").set({
    enabled: true,
    policy_version: "ai_policy_emulator_v1",
    prompt_version: "ai_coach_prompt_emulator_v1",
    cache_ttl_seconds: 86400,
    plans: {
      free: {daily_quota: 1, study_plan_enabled: false},
      premium_2: {daily_quota: 3, study_plan_enabled: true},
    },
  });

  const account = await createAccount();
  let call = await callable(
    "getAiCoachStatus",
    {protocolVersion: 1},
    account.idToken,
  );
  assert.equal(call.response.status, 200, JSON.stringify(call.body));
  let status = callableResult(call.body).quota;
  assert.equal(status.planId, "free");
  assert.equal(status.dailyLimit, 1);
  assert.equal(status.used, 0);

  const firstRequest = aiRequest(67, "session_ai_1");
  call = await callable("requestAiCoachInsight", firstRequest, account.idToken);
  assert.equal(call.response.status, 200, JSON.stringify(call.body));
  let result = callableResult(call.body);
  assert.equal(result.insight.provider, "emulator_stub");
  assert.equal(result.insight.studyPlan.length, 0);
  assert.equal(result.insight.fromServerCache, false);
  assert.equal(result.quota.used, 1);

  call = await callable("requestAiCoachInsight", firstRequest, account.idToken);
  assert.equal(call.response.status, 200, JSON.stringify(call.body));
  result = callableResult(call.body);
  assert.equal(result.insight.fromServerCache, true);
  assert.equal(result.quota.used, 1);

  call = await callable(
    "requestAiCoachInsight",
    aiRequest(68, "session_ai_2"),
    account.idToken,
  );
  assert.equal(call.response.status, 429, JSON.stringify(call.body));
  assert.equal(call.body.error.status, "RESOURCE_EXHAUSTED");
  assert.equal(call.body.error.details.quota.used, 1);

  call = await callable(
    "refreshSubscriptionEntitlement",
    {protocolVersion: 1},
    account.idToken,
  );
  assert.equal(call.response.status, 200, JSON.stringify(call.body));
  const entitlement = callableResult(call.body).entitlement;
  assert.equal(entitlement.planId, "premium_2");
  assert.equal(entitlement.source, "revenuecat");
  call = await callable(
    "getAiCoachStatus",
    {protocolVersion: 1},
    account.idToken,
  );
  status = callableResult(call.body).quota;
  assert.equal(status.planId, "premium_2");
  assert.equal(status.dailyLimit, 3);
  assert.equal(status.used, 1);

  call = await callable(
    "requestAiCoachInsight",
    aiRequest(68, "session_ai_2"),
    account.idToken,
  );
  assert.equal(call.response.status, 200, JSON.stringify(call.body));
  result = callableResult(call.body);
  assert.equal(result.insight.studyPlan.length, 1);
  assert.equal(result.quota.used, 2);

  call = await callable("requestAiCoachInsight", firstRequest, account.idToken);
  assert.equal(call.response.status, 200, JSON.stringify(call.body));
  result = callableResult(call.body);
  assert.equal(result.insight.fromServerCache, false);
  assert.equal(result.insight.studyPlan.length, 1);
  assert.equal(result.quota.used, 3);

  call = await callable("requestAiCoachInsight", firstRequest, account.idToken);
  assert.equal(call.response.status, 200, JSON.stringify(call.body));
  result = callableResult(call.body);
  assert.equal(result.insight.fromServerCache, true);
  assert.equal(result.quota.used, 3);

  const tampered = aiRequest(70, "session_tampered");
  tampered.context.scorePercentage = 99;
  call = await callable("requestAiCoachInsight", tampered, account.idToken);
  assert.equal(call.response.status, 400, JSON.stringify(call.body));
  assert.equal(call.body.error.status, "INVALID_ARGUMENT");

  await deleteApp(adminApp);
});

function aiRequest(scorePercentage, sourceSessionId) {
  const context = {
    schemaVersion: 1,
    sourceSessionId,
    examId: "cpns",
    testId: "tiu",
    scorePercentage,
    completedAt: "2026-09-11T09:00:00.000Z",
    topWeaknesses: [{
      taxonomyNodeId: "ratio",
      label: "Perbandingan",
      weaknessBasisPoints: 7000,
      confidenceBasisPoints: 8000,
      sampleSize: 4,
      trend: "stable",
      evidence: ["Akurasi masih di bawah target."],
    }],
    recommendation: {
      type: "adaptiveDrill",
      targetTaxonomyId: "ratio",
      targetLabel: "Perbandingan",
      reasonCode: "repeatedLowAccuracy",
      reason: "Kesalahan muncul berulang.",
      expectedBenefit: "Perkuat ketepatan rasio.",
      estimatedMinutes: 15,
      confidenceBasisPoints: 8000,
    },
  };
  return {
    protocolVersion: 1,
    contextKey: crypto
      .createHash("sha256")
      .update(canonicalJson(context))
      .digest("hex"),
    context,
  };
}

async function createAccount() {
  const response = await fetch(
    `http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: `ai-coach-${Date.now()}@example.com`,
        password: "test-password-123",
        returnSecureToken: true,
      }),
    },
  );
  const body = await response.json();
  assert.equal(response.status, 200, JSON.stringify(body));
  return body;
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
