"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {Timestamp} = require("firebase-admin/firestore");
const {capability, digest, TTL_MS, currentStatus, validateRequest, emulatorEnabled, manifest} = require("../web_link_service");
const {fixture} = require("../scripts/seed_web_link_emulator");

test("capabilities use 256-bit CSPRNG input and hash-only representation", () => {
  const tokens = new Set();
  for (let i = 0; i < 1024; i++) {
    const token = capability();
    assert.match(token.raw, /^[A-Za-z0-9_-]{43}$/);
    assert.equal(Buffer.from(token.raw, "base64url").length, 32);
    assert.equal(token.hash, digest(token.raw));
    assert.match(token.hash, /^[a-f0-9]{64}$/);
    assert.notEqual(token.hash, token.raw);
    tokens.add(token.raw);
  }
  assert.equal(tokens.size, 1024);
});

test("server expiry is exact and terminal states never reactivate", () => {
  assert.equal(TTL_MS, 43200000);
  const expiresAt = Timestamp.fromMillis(TTL_MS);
  assert.equal(currentStatus({status: "active", expiresAt}, TTL_MS - 1), "active");
  assert.equal(currentStatus({status: "active", expiresAt}, TTL_MS), "expired");
  for (const status of ["expired", "revoked", "completed", "timeout"]) {
    assert.equal(currentStatus({status, expiresAt}, 0), status);
    assert.equal(currentStatus({status, expiresAt}, TTL_MS + 1), status);
  }
  assert.throws(() => currentStatus({status: "unknown", expiresAt}, 0));
});

test("strict requests reject owner/time/ttl/score injection and malformed IDs", () => {
  const valid = {protocolVersion: 1, requestId: "r".repeat(32), tryoutId: "w2-synthetic", contentFingerprint: fixture.contentFingerprint};
  const fields = ["requestId", "tryoutId", "contentFingerprint"];
  assert.deepEqual(validateRequest(valid, fields), valid);
  for (const key of ["ownerUid", "expiresAtMs", "ttl", "score", "launchUrl"]) {
    assert.throws(() => validateRequest({...valid, [key]: "secret"}, fields), (e) =>
      e.code === "invalid-argument" && !String(e).includes("secret"));
  }
  for (const value of [null, [], "secret", {...valid, tryoutId: "../other"}, {...valid, requestId: "short"}, {...valid, contentFingerprint: 123}, {...valid, tryoutId: "w2-synthetic\n"}, {...valid, contentFingerprint: "a".repeat(64) + "\n"}]) {
    assert.throws(() => validateRequest(value, fields));
  }
});

test("W2 requires all emulator gates; manifests never accept draft or published substitutes", () => {
  const env = {FUNCTIONS_EMULATOR: "true", EXAMCOACH_WEB_LINKS_ENABLED: "true", GCLOUD_PROJECT: "demo-examcoach", FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080"};
  assert.equal(emulatorEnabled(env), true);
  for (const key of Object.keys(env)) assert.equal(emulatorEnabled({...env, [key]: ""}), false);
  assert.equal(emulatorEnabled({...env, GCLOUD_PROJECT: "live-examcoach"}), false);
  assert.ok(manifest("w2-synthetic", fixture));
  for (const validationStatus of ["published", "draft", "validated"]) {
    assert.equal(manifest("w2-synthetic", {...fixture, validationStatus}), null);
  }
});
