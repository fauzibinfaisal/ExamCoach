"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {OpenAiCoachProvider} = require("../openai_ai_provider");

test("OpenAI adapter requests strict structured output without storing response", async () => {
  let captured;
  const provider = new OpenAiCoachProvider({
    apiKey: "test-secret-key",
    model: "test-model",
    fetchImpl: async (url, options) => {
      captured = {url, options, body: JSON.parse(options.body)};
      return {
        ok: true,
        json: async () => ({
          model: "test-model-2026",
          output_text: JSON.stringify({
            summary: "Ringkasan",
            weakness_explanation: "Penjelasan",
            why_it_matters: "Alasan",
            study_plan: [],
            motivation: "Motivasi",
          }),
          usage: {input_tokens: 100, output_tokens: 50, total_tokens: 150},
        }),
      };
    },
  });
  const result = await provider.generate({
    context: {scorePercentage: 50},
    studyPlanEnabled: false,
    uid: "firebase-user-1",
  });

  assert.equal(captured.url, "https://api.openai.com/v1/responses");
  assert.equal(captured.options.headers.authorization, "Bearer test-secret-key");
  assert.equal(captured.body.store, false);
  assert.equal(captured.body.text.format.type, "json_schema");
  assert.equal(captured.body.text.format.strict, true);
  assert.equal(captured.body.safety_identifier.length, 64);
  assert.equal(result.provider, "openai");
  assert.equal(result.model, "test-model-2026");
  assert.equal(result.usage.totalTokens, 150);
});
