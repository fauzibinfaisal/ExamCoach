"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {validateAnalyticsProperties} = require("../analytics_contract");

test("accepts allow-listed scalar analytics properties", () => {
  assert.deepEqual(
    validateAnalyticsProperties("result_viewed", {sessionId: "session_1"}),
    {sessionId: "session_1"},
  );
});

test("rejects unknown or privacy-risk analytics data", () => {
  assert.throws(
    () => validateAnalyticsProperties("unknown_event", {}),
    /not registered/,
  );
  assert.throws(
    () => validateAnalyticsProperties("result_viewed", {email: "a@example.com"}),
    /not allowed/,
  );
  assert.throws(
    () => validateAnalyticsProperties("result_viewed", {sessionId: "x".repeat(241)}),
    /unsafe/,
  );
});
