"use strict";

const {normalizeAiCoachPolicy} = require("./ai_coach_core");

class RevenueCatError extends Error {
  constructor(message, {retryable = false} = {}) {
    super(message);
    this.name = "RevenueCatError";
    this.retryable = retryable;
  }
}

class EntitlementServiceError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "EntitlementServiceError";
    this.code = code;
  }
}

class RevenueCatSubscriberProvider {
  constructor({apiKey, entitlementPlans, fetchImpl = fetch}) {
    if (typeof apiKey !== "string" || apiKey.length < 10) {
      throw new RevenueCatError("RevenueCat server API key is not configured");
    }
    if (!entitlementPlans || typeof entitlementPlans !== "object" ||
        Array.isArray(entitlementPlans)) {
      throw new RevenueCatError("RevenueCat entitlement mapping is invalid");
    }
    const entries = Object.entries(entitlementPlans);
    if (entries.length < 1 || entries.length > 10) {
      throw new RevenueCatError("RevenueCat entitlement mapping is empty");
    }
    this.apiKey = apiKey;
    this.entitlementPlans = Object.fromEntries(entries.map(([key, value]) => [
      safeId(key, "RevenueCat entitlement ID"),
      safeId(value, "AI policy plan ID"),
    ]));
    this.fetchImpl = fetchImpl;
  }

  async getActiveEntitlements(uid, now) {
    let response;
    try {
      response = await this.fetchImpl(
        `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`,
        {
          method: "GET",
          headers: {
            authorization: `Bearer ${this.apiKey}`,
            "content-type": "application/json",
          },
          signal: AbortSignal.timeout(15000),
        },
      );
    } catch (error) {
      throw new RevenueCatError(`RevenueCat request failed: ${error.message}`, {
        retryable: true,
      });
    }
    if (!response.ok) {
      const body = await response.text();
      throw new RevenueCatError(
        `RevenueCat returned HTTP ${response.status}: ${body.slice(0, 240)}`,
        {retryable: response.status === 429 || response.status >= 500},
      );
    }
    const body = await response.json();
    const entitlements = body?.subscriber?.entitlements;
    if (!entitlements || typeof entitlements !== "object" ||
        Array.isArray(entitlements)) {
      throw new RevenueCatError("RevenueCat customer response is invalid");
    }
    const active = [];
    for (const [entitlementId, planId] of Object.entries(this.entitlementPlans)) {
      const entitlement = entitlements[entitlementId];
      if (!entitlement || typeof entitlement !== "object") continue;
      const expiresAt = effectiveExpiry(entitlement);
      if (expiresAt && expiresAt.getTime() <= now.getTime()) continue;
      active.push({entitlementId, planId, expiresAt});
    }
    return active;
  }
}

class EmulatorRevenueCatSubscriberProvider {
  async getActiveEntitlements(uid, now) {
    return [{
      entitlementId: "emulator_premium_2",
      planId: "premium_2",
      expiresAt: new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000),
    }];
  }
}

class RevenueCatEntitlementService {
  constructor({database, providerFactory, now = () => new Date()}) {
    this.database = database;
    this.providerFactory = providerFactory;
    this.now = now;
  }

  async refresh(uid) {
    const now = utcNow(this.now);
    const policySnapshot = await this.database
      .collection("config")
      .doc("ai_coach_policy")
      .get();
    if (!policySnapshot.exists) {
      throw new EntitlementServiceError(
        "failed-precondition",
        "Kebijakan paket belum dikonfigurasi.",
      );
    }
    let policy;
    try {
      policy = normalizeAiCoachPolicy(policySnapshot.data());
    } catch (_) {
      throw new EntitlementServiceError(
        "failed-precondition",
        "Kebijakan paket tidak valid.",
      );
    }

    let candidates;
    try {
      candidates = await this.providerFactory().getActiveEntitlements(uid, now);
    } catch (error) {
      if (error instanceof RevenueCatError) {
        throw new EntitlementServiceError(
          error.retryable ? "unavailable" : "failed-precondition",
          error.retryable
            ? "Status langganan belum dapat diverifikasi. Coba lagi nanti."
            : "Konfigurasi verifikasi langganan belum siap.",
        );
      }
      throw error;
    }

    const eligible = candidates
      .filter((candidate) => Object.hasOwn(policy.plans, candidate.planId))
      .sort((left, right) => comparePlans(policy, left, right));
    const selected = eligible[0] ?? null;
    const entitlement = selected == null
      ? {
        plan_id: "free",
        status: "inactive",
        source: "revenuecat",
        checked_at: now.toISOString(),
      }
      : {
        plan_id: selected.planId,
        status: "active",
        source: "revenuecat",
        revenuecat_entitlement_id: selected.entitlementId,
        expires_at: selected.expiresAt?.toISOString() ?? null,
        checked_at: now.toISOString(),
      };
    await this.database
      .collection("users")
      .doc(uid)
      .collection("entitlements")
      .doc("current")
      .set(entitlement);
    return {
      planId: entitlement.plan_id,
      status: entitlement.status,
      source: entitlement.source,
      entitlementId: entitlement.revenuecat_entitlement_id ?? null,
      expiresAt: entitlement.expires_at ?? null,
      checkedAt: entitlement.checked_at,
    };
  }
}

function comparePlans(policy, left, right) {
  const leftPolicy = policy.plans[left.planId];
  const rightPolicy = policy.plans[right.planId];
  const byQuota = rightPolicy.dailyQuota - leftPolicy.dailyQuota;
  if (byQuota !== 0) return byQuota;
  const bySchedule = Number(rightPolicy.studyPlanEnabled) -
    Number(leftPolicy.studyPlanEnabled);
  if (bySchedule !== 0) return bySchedule;
  return left.planId.localeCompare(right.planId);
}

function effectiveExpiry(entitlement) {
  if (!Object.hasOwn(entitlement, "expires_date")) {
    throw new RevenueCatError("RevenueCat entitlement expiry is missing");
  }
  const values = [entitlement.expires_date, entitlement.grace_period_expires_date]
    .filter((value) => typeof value === "string")
    .map((value) => new Date(value))
    .filter((value) => Number.isFinite(value.getTime()));
  if (entitlement.expires_date === null) return null;
  if (values.length === 0) {
    throw new RevenueCatError("RevenueCat entitlement expiry is invalid");
  }
  return values.reduce((latest, value) =>
    value.getTime() > latest.getTime() ? value : latest);
}

function utcNow(clock) {
  const value = clock();
  if (!(value instanceof Date) || !Number.isFinite(value.getTime())) {
    throw new EntitlementServiceError("internal", "Subscription clock is invalid.");
  }
  return new Date(value.toISOString());
}

function safeId(value, path) {
  if (typeof value !== "string" || value.trim().length === 0 ||
      value.length > 240 || value.includes("/")) {
    throw new RevenueCatError(`${path} is invalid`);
  }
  return value.trim();
}

module.exports = {
  EmulatorRevenueCatSubscriberProvider,
  EntitlementServiceError,
  RevenueCatEntitlementService,
  RevenueCatError,
  RevenueCatSubscriberProvider,
};
