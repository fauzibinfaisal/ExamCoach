"use strict";

const crypto = require("node:crypto");

const OUTPUT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    summary: {type: "string"},
    weakness_explanation: {type: "string"},
    why_it_matters: {type: "string"},
    study_plan: {
      type: "array",
      maxItems: 7,
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          title: {type: "string"},
          action: {type: "string"},
          duration_minutes: {type: "integer", minimum: 5, maximum: 180},
        },
        required: ["title", "action", "duration_minutes"],
      },
    },
    motivation: {type: "string"},
  },
  required: [
    "summary",
    "weakness_explanation",
    "why_it_matters",
    "study_plan",
    "motivation",
  ],
};

class AiProviderError extends Error {
  constructor(message, {retryable = false} = {}) {
    super(message);
    this.name = "AiProviderError";
    this.retryable = retryable;
  }
}

class OpenAiCoachProvider {
  constructor({apiKey, model, fetchImpl = fetch}) {
    if (typeof apiKey !== "string" || apiKey.length < 10) {
      throw new AiProviderError("OpenAI API key is not configured");
    }
    if (typeof model !== "string" || model.trim().length === 0) {
      throw new AiProviderError("OpenAI model is not configured");
    }
    this.apiKey = apiKey;
    this.model = model.trim();
    this.fetchImpl = fetchImpl;
  }

  async generate({context, studyPlanEnabled, uid}) {
    let response;
    try {
      response = await this.fetchImpl("https://api.openai.com/v1/responses", {
        method: "POST",
        headers: {
          authorization: `Bearer ${this.apiKey}`,
          "content-type": "application/json",
        },
        signal: AbortSignal.timeout(30000),
        body: JSON.stringify({
          model: this.model,
          store: false,
          max_output_tokens: 700,
          safety_identifier: crypto.createHash("sha256").update(uid).digest("hex"),
          prompt_cache_key: "examcoach-ai-coach-v1",
          instructions: [
            "Anda adalah AI Coach ExamCoach yang ringkas, tenang, dan profesional.",
            "Gunakan hanya fakta pada konteks terstruktur yang diberikan.",
            "Jangan menghitung ulang nilai, menentukan kebenaran jawaban, mengubah kelemahan, atau memilih soal.",
            "Jangan menjanjikan kelulusan atau mengarang percentile/readiness.",
            "Tulis Bahasa Indonesia yang jelas. Jika bukti terbatas, katakan secara eksplisit.",
            studyPlanEnabled
              ? "Buat rencana belajar praktis yang mengikuti rekomendasi terstruktur."
              : "Kosongkan study_plan karena paket pengguna tidak membuka jadwal personal.",
          ].join(" "),
          input: JSON.stringify({
            context,
            capabilities: {studyPlanEnabled},
          }),
          text: {
            format: {
              type: "json_schema",
              name: "examcoach_ai_coach_v1",
              strict: true,
              schema: OUTPUT_SCHEMA,
            },
          },
        }),
      });
    } catch (error) {
      throw new AiProviderError(`OpenAI request failed: ${error.message}`, {
        retryable: true,
      });
    }
    if (!response.ok) {
      const body = await response.text();
      throw new AiProviderError(
        `OpenAI returned HTTP ${response.status}: ${body.slice(0, 240)}`,
        {retryable: response.status === 429 || response.status >= 500},
      );
    }
    const body = await response.json();
    const outputText = extractOutputText(body);
    let output;
    try {
      output = JSON.parse(outputText);
    } catch (_) {
      throw new AiProviderError("OpenAI returned invalid structured JSON");
    }
    return {
      provider: "openai",
      model: typeof body.model === "string" ? body.model : this.model,
      output,
      usage: normalizeUsage(body.usage),
    };
  }
}

class EmulatorAiCoachProvider {
  async generate({context, studyPlanEnabled}) {
    const weakness = context.topWeaknesses[0];
    return {
      provider: "emulator_stub",
      model: "deterministic_v1",
      output: {
        summary: `Skor terbaru ${context.scorePercentage}. Fokus utama berada pada ${weakness.label}.`,
        weakness_explanation: `Data menunjukkan ${weakness.label} perlu diprioritaskan dengan keyakinan ${Math.round(weakness.confidenceBasisPoints / 100)}%.`,
        why_it_matters: context.recommendation.reason,
        study_plan: studyPlanEnabled
          ? [{
            title: `Latihan ${context.recommendation.targetLabel}`,
            action: context.recommendation.expectedBenefit,
            duration_minutes: context.recommendation.estimatedMinutes,
          }]
          : [],
        motivation: "Kerjakan satu fokus kecil dengan konsisten, lalu ukur perubahan dari hasil berikutnya.",
      },
      usage: {inputTokens: 0, outputTokens: 0, totalTokens: 0},
    };
  }
}

function extractOutputText(body) {
  if (typeof body.output_text === "string" && body.output_text.length > 0) {
    return body.output_text;
  }
  if (Array.isArray(body.output)) {
    for (const item of body.output) {
      if (!Array.isArray(item?.content)) continue;
      for (const content of item.content) {
        if (content?.type === "output_text" && typeof content.text === "string") {
          return content.text;
        }
      }
    }
  }
  throw new AiProviderError("OpenAI response does not contain output text");
}

function normalizeUsage(value) {
  const usage = value && typeof value === "object" ? value : {};
  return {
    inputTokens: safeInteger(usage.input_tokens),
    outputTokens: safeInteger(usage.output_tokens),
    totalTokens: safeInteger(usage.total_tokens),
  };
}

function safeInteger(value) {
  return Number.isSafeInteger(value) && value >= 0 ? value : 0;
}

module.exports = {
  AiProviderError,
  EmulatorAiCoachProvider,
  OpenAiCoachProvider,
  OUTPUT_SCHEMA,
};
