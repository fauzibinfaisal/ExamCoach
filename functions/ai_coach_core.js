"use strict";

const crypto = require("node:crypto");
const {ProtocolError, canonicalJson} = require("./sync_core");

const TRENDS = new Set([
  "improving",
  "stable",
  "declining",
  "insufficientData",
]);
const ACTIVE_ENTITLEMENTS = new Set(["active", "trialing"]);
const GUARANTEE_PATTERNS = [
  /pasti\s+lulus/i,
  /dijamin\s+lulus/i,
  /jaminan\s+lulus/i,
  /100\s*%\s+lulus/i,
];

function normalizeAiCoachRequest(source) {
  const root = object(source, "request");
  const contextKey = hexHash(root.contextKey, "contextKey");
  const sourceContext = object(root.context, "context");
  if (integer(sourceContext.schemaVersion, "context.schemaVersion") !== 1) {
    throw new ProtocolError("context.schemaVersion must be 1");
  }
  const weaknesses = array(sourceContext.topWeaknesses, "context.topWeaknesses");
  if (weaknesses.length < 1 || weaknesses.length > 3) {
    throw new ProtocolError("context.topWeaknesses must contain 1 to 3 items");
  }
  const normalized = {
    schemaVersion: 1,
    sourceSessionId: safeId(
      sourceContext.sourceSessionId,
      "context.sourceSessionId",
    ),
    examId: safeId(sourceContext.examId, "context.examId"),
    testId: safeId(sourceContext.testId, "context.testId"),
    scorePercentage: boundedInteger(
      sourceContext.scorePercentage,
      "context.scorePercentage",
      0,
      100,
    ),
    completedAt: utcTime(sourceContext.completedAt, "context.completedAt"),
    topWeaknesses: weaknesses.map((value, index) =>
      normalizeWeakness(value, index)),
    recommendation: normalizeRecommendation(sourceContext.recommendation),
  };
  const expectedKey = crypto
    .createHash("sha256")
    .update(canonicalJson(normalized))
    .digest("hex");
  if (expectedKey !== contextKey) {
    throw new ProtocolError("contextKey does not match canonical context");
  }
  return {contextKey, context: normalized};
}

function normalizeWeakness(source, index) {
  const value = object(source, `context.topWeaknesses[${index}]`);
  const evidence = array(value.evidence, `context.topWeaknesses[${index}].evidence`);
  if (evidence.length > 3) {
    throw new ProtocolError("weakness evidence exceeds 3 items");
  }
  const trend = string(value.trend, `context.topWeaknesses[${index}].trend`);
  if (!TRENDS.has(trend)) throw new ProtocolError("unsupported weakness trend");
  return {
    taxonomyNodeId: safeId(
      value.taxonomyNodeId,
      `context.topWeaknesses[${index}].taxonomyNodeId`,
    ),
    label: boundedString(value.label, "weakness label", 120),
    weaknessBasisPoints: boundedInteger(
      value.weaknessBasisPoints,
      "weaknessBasisPoints",
      0,
      10000,
    ),
    confidenceBasisPoints: boundedInteger(
      value.confidenceBasisPoints,
      "confidenceBasisPoints",
      0,
      10000,
    ),
    sampleSize: boundedInteger(value.sampleSize, "sampleSize", 1, 1000000),
    trend,
    evidence: evidence.map((item) => boundedString(item, "evidence", 240)),
  };
}

function normalizeRecommendation(source) {
  const value = object(source, "context.recommendation");
  return {
    type: safeId(value.type, "recommendation.type"),
    targetTaxonomyId: safeId(
      value.targetTaxonomyId,
      "recommendation.targetTaxonomyId",
    ),
    targetLabel: boundedString(
      value.targetLabel,
      "recommendation.targetLabel",
      120,
    ),
    reasonCode: safeId(value.reasonCode, "recommendation.reasonCode"),
    reason: boundedString(value.reason, "recommendation.reason", 500),
    expectedBenefit: boundedString(
      value.expectedBenefit,
      "recommendation.expectedBenefit",
      300,
    ),
    estimatedMinutes: boundedInteger(
      value.estimatedMinutes,
      "recommendation.estimatedMinutes",
      1,
      360,
    ),
    confidenceBasisPoints: boundedInteger(
      value.confidenceBasisPoints,
      "recommendation.confidenceBasisPoints",
      0,
      10000,
    ),
  };
}

function normalizeAiCoachPolicy(source) {
  const value = object(source, "AI Coach policy");
  const planValues = object(value.plans, "AI Coach policy plans");
  const planIds = Object.keys(planValues);
  if (!planIds.includes("free") || planIds.length > 10) {
    throw new ProtocolError("AI Coach policy requires a free plan");
  }
  const plans = {};
  for (const planId of planIds) {
    safeId(planId, "plan ID");
    const plan = object(planValues[planId], `plan ${planId}`);
    plans[planId] = {
      dailyQuota: boundedInteger(
        plan.daily_quota,
        `plan ${planId}.daily_quota`,
        0,
        100,
      ),
      studyPlanEnabled: boolean(
        plan.study_plan_enabled,
        `plan ${planId}.study_plan_enabled`,
      ),
    };
  }
  return {
    enabled: boolean(value.enabled, "AI Coach policy enabled"),
    policyVersion: safeId(value.policy_version, "AI Coach policy version"),
    promptVersion: safeId(value.prompt_version, "AI Coach prompt version"),
    cacheTtlSeconds: boundedInteger(
      value.cache_ttl_seconds,
      "AI Coach cache_ttl_seconds",
      60,
      604800,
    ),
    plans,
  };
}

function resolveEntitlement(source, policy, now) {
  if (!source) return {planId: "free", status: "active", source: "default"};
  const value = object(source, "entitlement");
  const status = string(value.status, "entitlement.status");
  const requestedPlan = safeId(value.plan_id, "entitlement.plan_id");
  const expiresAt = optionalTime(value.expires_at);
  const active = ACTIVE_ENTITLEMENTS.has(status) &&
    (!expiresAt || expiresAt.getTime() > now.getTime()) &&
    Object.hasOwn(policy.plans, requestedPlan);
  return {
    planId: active ? requestedPlan : "free",
    status: active ? status : "inactive",
    source: typeof value.source === "string" ? value.source : "unknown",
  };
}

function quotaStatus(policy, entitlement, used, now) {
  const plan = policy.plans[entitlement.planId] ?? policy.plans.free;
  const normalizedUsed = Math.min(Math.max(integerOrZero(used), 0), plan.dailyQuota);
  return {
    enabled: policy.enabled,
    policyVersion: policy.policyVersion,
    planId: entitlement.planId,
    entitlementStatus: entitlement.status,
    dailyLimit: plan.dailyQuota,
    used: normalizedUsed,
    resetsAt: nextUtcDay(now).toISOString(),
  };
}

function validateAiCoachOutput(source, {studyPlanEnabled}) {
  const value = object(source, "AI Coach output");
  const studyPlan = array(value.study_plan, "output.study_plan");
  const output = {
    summary: boundedString(value.summary, "output.summary", 600),
    weaknessExplanation: boundedString(
      value.weakness_explanation,
      "output.weakness_explanation",
      900,
    ),
    whyItMatters: boundedString(
      value.why_it_matters,
      "output.why_it_matters",
      600,
    ),
    studyPlan: studyPlanEnabled
      ? normalizeStudyPlan(studyPlan)
      : [],
    motivation: boundedString(value.motivation, "output.motivation", 300),
  };
  const combined = [
    output.summary,
    output.weaknessExplanation,
    output.whyItMatters,
    output.motivation,
    ...output.studyPlan.flatMap((item) => [item.title, item.action]),
  ].join(" ");
  if (GUARANTEE_PATTERNS.some((pattern) => pattern.test(combined))) {
    throw new ProtocolError("AI Coach output contains a passing guarantee");
  }
  return output;
}

function normalizeStudyPlan(source) {
  const items = array(source, "output.study_plan");
  if (items.length < 1 || items.length > 7) {
    throw new ProtocolError("output.study_plan must contain 1 to 7 items");
  }
  return items.map((sourceItem, index) => {
    const item = object(sourceItem, `output.study_plan[${index}]`);
    return {
      title: boundedString(item.title, "study plan title", 120),
      action: boundedString(item.action, "study plan action", 400),
      durationMinutes: boundedInteger(
        item.duration_minutes,
        "study plan duration_minutes",
        5,
        180,
      ),
    };
  });
}

function dayKey(now) {
  return now.toISOString().slice(0, 10);
}

function nextUtcDay(now) {
  return new Date(Date.UTC(
    now.getUTCFullYear(),
    now.getUTCMonth(),
    now.getUTCDate() + 1,
  ));
}

function publicInsight(value, fromServerCache) {
  return {
    contextKey: value.context_key,
    summary: value.summary,
    weaknessExplanation: value.weakness_explanation,
    whyItMatters: value.why_it_matters,
    studyPlan: Array.isArray(value.study_plan) ? value.study_plan : [],
    motivation: value.motivation,
    generatedAt: value.generated_at,
    expiresAt: value.expires_at,
    provider: value.provider,
    model: value.model,
    promptVersion: value.prompt_version,
    fromServerCache,
  };
}

function safeId(value, path) {
  const result = boundedString(value, path, 240);
  if (result.includes("/")) throw new ProtocolError(`${path} is not a safe ID`);
  return result;
}

function hexHash(value, path) {
  const result = string(value, path);
  if (!/^[a-f0-9]{64}$/.test(result)) {
    throw new ProtocolError(`${path} must be a SHA-256 hash`);
  }
  return result;
}

function boundedString(value, path, maximum) {
  const result = string(value, path).trim();
  if (result.length > maximum) throw new ProtocolError(`${path} is too long`);
  return result;
}

function string(value, path) {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new ProtocolError(`${path} must be a non-empty string`);
  }
  return value;
}

function integer(value, path) {
  if (!Number.isSafeInteger(value)) throw new ProtocolError(`${path} must be an integer`);
  return value;
}

function boundedInteger(value, path, minimum, maximum) {
  const result = integer(value, path);
  if (result < minimum || result > maximum) {
    throw new ProtocolError(`${path} is outside allowed bounds`);
  }
  return result;
}

function integerOrZero(value) {
  return Number.isSafeInteger(value) ? value : 0;
}

function boolean(value, path) {
  if (typeof value !== "boolean") throw new ProtocolError(`${path} must be boolean`);
  return value;
}

function object(value, path) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ProtocolError(`${path} must be an object`);
  }
  return value;
}

function array(value, path) {
  if (!Array.isArray(value)) throw new ProtocolError(`${path} must be an array`);
  return value;
}

function utcTime(value, path) {
  const result = string(value, path);
  if (!result.endsWith("Z") || !Number.isFinite(Date.parse(result))) {
    throw new ProtocolError(`${path} must be an ISO-8601 UTC timestamp`);
  }
  return new Date(result).toISOString();
}

function optionalTime(value) {
  if (value == null) return null;
  if (value instanceof Date) return value;
  if (typeof value.toDate === "function") return value.toDate();
  if (typeof value === "string" && Number.isFinite(Date.parse(value))) {
    return new Date(value);
  }
  throw new ProtocolError("entitlement.expires_at is invalid");
}

module.exports = {
  dayKey,
  nextUtcDay,
  normalizeAiCoachPolicy,
  normalizeAiCoachRequest,
  publicInsight,
  quotaStatus,
  resolveEntitlement,
  validateAiCoachOutput,
};
