"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const test = require("node:test");
const {
  normalizeAiCoachPolicy,
  normalizeAiCoachRequest,
  quotaStatus,
  resolveEntitlement,
  validateAiCoachOutput,
} = require("../ai_coach_core");
const {ProtocolError, canonicalJson} = require("../sync_core");

test("normalizes a canonical deterministic learning context", () => {
  const source = request();
  const normalized = normalizeAiCoachRequest(source);
  assert.equal(normalized.context.sourceSessionId, "session_1");
  assert.equal(normalized.context.scorePercentage, 67);
  assert.equal(normalized.context.topWeaknesses[0].taxonomyNodeId, "ratio");
});

test("rejects tampered context and passing guarantees", () => {
  const source = request();
  source.context.scorePercentage = 100;
  assert.throws(() => normalizeAiCoachRequest(source), /contextKey/);
  assert.throws(
    () => validateAiCoachOutput({
      ...providerOutput(),
      motivation: "Kamu pasti lulus jika mengikuti ini.",
    }, {studyPlanEnabled: true}),
    ProtocolError,
  );
});

test("policy and entitlement resolve quota without trusting the client", () => {
  const policy = normalizeAiCoachPolicy(policyDocument());
  const now = new Date("2026-09-11T10:00:00.000Z");
  const premium = resolveEntitlement({
    plan_id: "premium_2",
    status: "active",
    source: "revenuecat",
    expires_at: "2026-10-01T00:00:00.000Z",
  }, policy, now);
  const expired = resolveEntitlement({
    plan_id: "premium_2",
    status: "active",
    expires_at: "2026-09-01T00:00:00.000Z",
  }, policy, now);
  assert.equal(premium.planId, "premium_2");
  assert.equal(expired.planId, "free");
  assert.deepEqual(quotaStatus(policy, premium, 1, now), {
    enabled: true,
    policyVersion: "ai_policy_test_v1",
    planId: "premium_2",
    entitlementStatus: "active",
    dailyLimit: 3,
    used: 1,
    resetsAt: "2026-09-12T00:00:00.000Z",
  });
});

test("free policy strips study schedule from otherwise valid output", () => {
  const output = validateAiCoachOutput(providerOutput(), {
    studyPlanEnabled: false,
  });
  assert.deepEqual(output.studyPlan, []);
});

function request() {
  const context = {
    schemaVersion: 1,
    sourceSessionId: "session_1",
    examId: "cpns",
    testId: "tiu",
    scorePercentage: 67,
    completedAt: "2026-09-11T09:00:00.000Z",
    topWeaknesses: [{
      taxonomyNodeId: "ratio",
      label: "Perbandingan",
      weaknessBasisPoints: 7200,
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

function policyDocument() {
  return {
    enabled: true,
    policy_version: "ai_policy_test_v1",
    prompt_version: "ai_coach_prompt_test_v1",
    cache_ttl_seconds: 86400,
    plans: {
      free: {daily_quota: 1, study_plan_enabled: false},
      premium_1: {daily_quota: 1, study_plan_enabled: true},
      premium_2: {daily_quota: 3, study_plan_enabled: true},
    },
  };
}

function providerOutput() {
  return {
    summary: "Skor terbaru menunjukkan fokus yang jelas.",
    weakness_explanation: "Perbandingan perlu diperkuat berdasarkan bukti.",
    why_it_matters: "Topik ini mendukung rekomendasi latihan berikutnya.",
    study_plan: [{
      title: "Latihan rasio",
      action: "Kerjakan drill yang sudah direkomendasikan.",
      duration_minutes: 15,
    }],
    motivation: "Fokus pada satu perbaikan yang dapat diukur.",
  };
}
