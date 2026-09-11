"use strict";

const crypto = require("node:crypto");
const {
  dayKey,
  normalizeAiCoachPolicy,
  normalizeAiCoachRequest,
  publicInsight,
  quotaStatus,
  resolveEntitlement,
  validateAiCoachOutput,
} = require("./ai_coach_core");
const {AiProviderError} = require("./openai_ai_provider");

class AiCoachServiceError extends Error {
  constructor(code, message, details) {
    super(message);
    this.name = "AiCoachServiceError";
    this.code = code;
    this.details = details;
  }
}

class AiCoachService {
  constructor({database, providerFactory, now = () => new Date()}) {
    this.database = database;
    this.providerFactory = providerFactory;
    this.now = now;
  }

  async getStatus(uid) {
    const now = this.#utcNow();
    const userRef = this.database.collection("users").doc(uid);
    const policyRef = this.database.collection("config").doc("ai_coach_policy");
    const entitlementRef = userRef.collection("entitlements").doc("current");
    const usageRef = userRef.collection("ai_usage").doc(dayKey(now));
    const [policySnapshot, entitlementSnapshot, usageSnapshot] = await Promise.all([
      policyRef.get(),
      entitlementRef.get(),
      usageRef.get(),
    ]);
    const policy = requirePolicy(policySnapshot);
    const entitlement = resolveEntitlement(
      entitlementSnapshot.exists ? entitlementSnapshot.data() : null,
      policy,
      now,
    );
    const used = usageSnapshot.exists ? usageSnapshot.data().count : 0;
    return quotaStatus(policy, entitlement, used, now);
  }

  async request(uid, source) {
    const normalized = normalizeAiCoachRequest(source);
    const now = this.#utcNow();
    const reservation = await this.#reserve(uid, normalized, now);
    if (reservation.cached) {
      return {
        insight: publicInsight(reservation.cached, true),
        quota: reservation.quota,
      };
    }

    try {
      const provider = this.providerFactory();
      const generated = await provider.generate({
        context: normalized.context,
        studyPlanEnabled: reservation.studyPlanEnabled,
        uid,
      });
      const output = validateAiCoachOutput(generated.output, {
        studyPlanEnabled: reservation.studyPlanEnabled,
      });
      const generatedAt = this.#utcNow();
      const expiresAt = new Date(
        generatedAt.getTime() + reservation.cacheTtlSeconds * 1000,
      );
      const insight = {
        schema_version: 1,
        context_key: normalized.contextKey,
        source_session_id: normalized.context.sourceSessionId,
        summary: output.summary,
        weakness_explanation: output.weaknessExplanation,
        why_it_matters: output.whyItMatters,
        study_plan: output.studyPlan,
        motivation: output.motivation,
        provider: generated.provider,
        model: generated.model,
        prompt_version: reservation.promptVersion,
        generated_at: generatedAt.toISOString(),
        expires_at: expiresAt.toISOString(),
        usage: generated.usage,
        study_plan_enabled: reservation.studyPlanEnabled,
      };
      await this.#finalize(uid, normalized.contextKey, reservation, insight);
      return {
        insight: publicInsight(insight, false),
        quota: reservation.quota,
      };
    } catch (error) {
      await this.#release(uid, normalized.contextKey, reservation);
      if (error instanceof AiCoachServiceError) throw error;
      if (error instanceof AiProviderError) {
        throw new AiCoachServiceError(
          error.retryable ? "unavailable" : "failed-precondition",
          error.retryable
            ? "Provider AI sedang tidak tersedia. Coba lagi nanti."
            : "Konfigurasi provider AI belum siap.",
        );
      }
      throw new AiCoachServiceError(
        "failed-precondition",
        "Respons provider AI tidak lolos validasi keamanan.",
      );
    }
  }

  async #reserve(uid, normalized, now) {
    const userRef = this.database.collection("users").doc(uid);
    const policyRef = this.database.collection("config").doc("ai_coach_policy");
    const entitlementRef = userRef.collection("entitlements").doc("current");
    const insightRef = userRef.collection("ai_insights").doc(normalized.contextKey);
    const requestRef = userRef.collection("ai_requests").doc(normalized.contextKey);
    const usageRef = userRef.collection("ai_usage").doc(dayKey(now));
    const attemptId = crypto.randomUUID();

    return this.database.runTransaction(async (transaction) => {
      const policySnapshot = await transaction.get(policyRef);
      const entitlementSnapshot = await transaction.get(entitlementRef);
      const insightSnapshot = await transaction.get(insightRef);
      const requestSnapshot = await transaction.get(requestRef);
      const usageSnapshot = await transaction.get(usageRef);
      const policy = requirePolicy(policySnapshot);
      const entitlement = resolveEntitlement(
        entitlementSnapshot.exists ? entitlementSnapshot.data() : null,
        policy,
        now,
      );
      const used = usageSnapshot.exists ? usageSnapshot.data().count : 0;
      const currentQuota = quotaStatus(policy, entitlement, used, now);
      if (!policy.enabled) {
        throw new AiCoachServiceError(
          "failed-precondition",
          "AI Coach dinonaktifkan oleh kebijakan server.",
        );
      }
      const cached = insightSnapshot.exists ? insightSnapshot.data() : null;
      if (cached && Date.parse(cached.expires_at) > now.getTime()) {
        const studyPlanEnabled =
          policy.plans[entitlement.planId].studyPlanEnabled;
        if (!studyPlanEnabled || cached.study_plan_enabled === true) {
          return {
            cached: studyPlanEnabled
              ? cached
              : {...cached, study_plan: []},
            quota: currentQuota,
          };
        }
      }
      if (currentQuota.used >= currentQuota.dailyLimit) {
        throw new AiCoachServiceError(
          "resource-exhausted",
          "Kuota AI Coach hari ini sudah habis.",
          {quota: currentQuota},
        );
      }

      if (requestSnapshot.exists) {
        const request = requestSnapshot.data();
        const startedAt = Date.parse(request.started_at);
        if (request.status === "generating" &&
            Number.isFinite(startedAt) &&
            now.getTime() - startedAt < 120000) {
          throw new AiCoachServiceError(
            "aborted",
            "Insight yang sama sedang dibuat. Coba lagi sebentar.",
          );
        }
      }

      const chargedUsed = currentQuota.used + 1;
      const chargedQuota = quotaStatus(policy, entitlement, chargedUsed, now);
      transaction.set(usageRef, {
        day_key: dayKey(now),
        count: chargedUsed,
        policy_version: policy.policyVersion,
        reset_at: chargedQuota.resetsAt,
        updated_at: now.toISOString(),
      }, {merge: true});
      transaction.set(requestRef, {
        context_key: normalized.contextKey,
        source_session_id: normalized.context.sourceSessionId,
        status: "generating",
        attempt_id: attemptId,
        charged_day_key: dayKey(now),
        started_at: now.toISOString(),
        updated_at: now.toISOString(),
      });
      return {
        cached: null,
        attemptId,
        chargedDayKey: dayKey(now),
        cacheTtlSeconds: policy.cacheTtlSeconds,
        promptVersion: policy.promptVersion,
        studyPlanEnabled:
          policy.plans[entitlement.planId].studyPlanEnabled,
        quota: chargedQuota,
      };
    });
  }

  async #finalize(uid, contextKey, reservation, insight) {
    const userRef = this.database.collection("users").doc(uid);
    const requestRef = userRef.collection("ai_requests").doc(contextKey);
    const insightRef = userRef.collection("ai_insights").doc(contextKey);
    await this.database.runTransaction(async (transaction) => {
      const requestSnapshot = await transaction.get(requestRef);
      if (!requestSnapshot.exists ||
          requestSnapshot.data().status !== "generating" ||
          requestSnapshot.data().attempt_id !== reservation.attemptId) {
        throw new AiCoachServiceError(
          "aborted",
          "Reservasi AI Coach sudah digantikan oleh permintaan lain.",
        );
      }
      transaction.set(insightRef, insight);
      transaction.update(requestRef, {
        status: "completed",
        completed_at: insight.generated_at,
        updated_at: insight.generated_at,
      });
    });
  }

  async #release(uid, contextKey, reservation) {
    if (!reservation?.attemptId || !reservation.chargedDayKey) return;
    const userRef = this.database.collection("users").doc(uid);
    const requestRef = userRef.collection("ai_requests").doc(contextKey);
    const usageRef = userRef.collection("ai_usage").doc(
      reservation.chargedDayKey,
    );
    try {
      await this.database.runTransaction(async (transaction) => {
        const requestSnapshot = await transaction.get(requestRef);
        const usageSnapshot = await transaction.get(usageRef);
        if (!requestSnapshot.exists ||
            requestSnapshot.data().status !== "generating" ||
            requestSnapshot.data().attempt_id !== reservation.attemptId) {
          return;
        }
        const count = usageSnapshot.exists &&
          Number.isSafeInteger(usageSnapshot.data().count)
          ? usageSnapshot.data().count
          : 0;
        transaction.set(usageRef, {
          count: Math.max(0, count - 1),
          updated_at: this.#utcNow().toISOString(),
        }, {merge: true});
        transaction.update(requestRef, {
          status: "failed",
          updated_at: this.#utcNow().toISOString(),
        });
      });
    } catch (_) {
      // A cleanup failure must not hide the original provider failure. The
      // reservation expires after two minutes and becomes safely replaceable.
    }
  }

  #utcNow() {
    const value = this.now();
    if (!(value instanceof Date) || !Number.isFinite(value.getTime())) {
      throw new AiCoachServiceError("internal", "AI Coach clock is invalid.");
    }
    return new Date(value.toISOString());
  }
}

function requirePolicy(snapshot) {
  if (!snapshot.exists) {
    throw new AiCoachServiceError(
      "failed-precondition",
      "Kebijakan AI Coach belum dikonfigurasi.",
    );
  }
  try {
    return normalizeAiCoachPolicy(snapshot.data());
  } catch (_) {
    throw new AiCoachServiceError(
      "failed-precondition",
      "Kebijakan AI Coach tidak valid.",
    );
  }
}

module.exports = {AiCoachService, AiCoachServiceError};
