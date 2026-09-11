"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  RevenueCatError,
  RevenueCatSubscriberProvider,
} = require("../revenuecat_entitlement");

test("RevenueCat adapter returns only mapped active entitlements", async () => {
  let request;
  const provider = new RevenueCatSubscriberProvider({
    apiKey: "sk_emulator_secret",
    entitlementPlans: {
      starter_access: "premium_1",
      advanced_access: "premium_2",
    },
    fetchImpl: async (url, options) => {
      request = {url, options};
      return response({
        subscriber: {
          entitlements: {
            starter_access: {expires_date: "2026-10-01T00:00:00.000Z"},
            advanced_access: {expires_date: "2026-09-01T00:00:00.000Z"},
            unknown_access: {expires_date: null},
          },
        },
      });
    },
  });

  const result = await provider.getActiveEntitlements(
    "firebase user/123",
    new Date("2026-09-11T00:00:00.000Z"),
  );

  assert.equal(
    request.url,
    "https://api.revenuecat.com/v1/subscribers/firebase%20user%2F123",
  );
  assert.equal(request.options.headers.authorization, "Bearer sk_emulator_secret");
  assert.deepEqual(result, [{
    entitlementId: "starter_access",
    planId: "premium_1",
    expiresAt: new Date("2026-10-01T00:00:00.000Z"),
  }]);
});

test("RevenueCat adapter treats malformed customer data as untrusted", async () => {
  const provider = new RevenueCatSubscriberProvider({
    apiKey: "sk_emulator_secret",
    entitlementPlans: {premium: "premium_1"},
    fetchImpl: async () => response({subscriber: {entitlements: []}}),
  });

  await assert.rejects(
    provider.getActiveEntitlements("user", new Date()),
    RevenueCatError,
  );
});

function response(body, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
    text: async () => JSON.stringify(body),
  };
}
