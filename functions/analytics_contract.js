"use strict";

const EVENT_PROPERTIES = new Map([
  ["practice_started", new Set(["sessionId", "mode"])],
  ["question_answered", new Set([
    "sessionId", "questionId", "taxonomyNodeId", "isCorrect", "timeSpentMs",
  ])],
  ["question_skipped", new Set([
    "sessionId", "questionId", "taxonomyNodeId", "mode",
  ])],
  ["answer_changed", new Set([
    "sessionId", "questionId", "fromOptionId", "toOptionId", "isCorrect",
  ])],
  ["practice_cancelled", new Set([
    "sessionId", "mode", "answeredCount", "skippedCount",
  ])],
  ["practice_expired", new Set(["sessionId", "mode", "inactiveForMs"])],
  ["question_review_viewed", new Set([
    "sessionId", "mode", "questionCount", "skippedCount",
  ])],
  ["practice_completed", new Set(["sessionId", "score", "skippedCount"])],
  ["drill_started", new Set(["sessionId", "mode"])],
  ["drill_completed", new Set(["sessionId", "score", "skippedCount"])],
  ["result_viewed", new Set(["sessionId"])],
  ["weakness_viewed", new Set(["sessionId"])],
  ["recommendation_viewed", new Set(["sessionId", "target"])],
  ["recommendation_clicked", new Set(["target"])],
  ["ai_insight_requested", new Set(["sessionId"])],
  ["ai_insight_generated", new Set([
    "sessionId", "provider", "model", "serverCache",
  ])],
  ["ai_insight_viewed", new Set(["sessionId", "provider"])],
  ["ai_quota_exhausted", new Set(["sessionId"])],
  ["paywall_viewed", new Set()],
  ["purchase_started", new Set(["packageId"])],
  ["subscription_started", new Set(["packageId", "planId"])],
  ["restore_purchase", new Set()],
]);

function validateAnalyticsProperties(eventName, properties) {
  const allowed = EVENT_PROPERTIES.get(eventName);
  if (!allowed) throw new Error("analytics event is not registered");
  if (!properties || Array.isArray(properties) || typeof properties !== "object") {
    throw new Error("analytics properties must be an object");
  }
  for (const [key, value] of Object.entries(properties)) {
    if (!allowed.has(key)) throw new Error("analytics property is not allowed");
    const validString = typeof value === "string" && value.length <= 240;
    const validNumber = typeof value === "number" && Number.isFinite(value);
    if (typeof value !== "boolean" && !validString && !validNumber) {
      throw new Error("analytics property value is unsafe");
    }
  }
  return properties;
}

module.exports = {EVENT_PROPERTIES, validateAnalyticsProperties};
