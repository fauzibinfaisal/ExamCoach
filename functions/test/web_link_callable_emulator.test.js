"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {WebLinkService, TTL_MS, digest} = require("../web_link_service");
const {fixture, seed} = require("../scripts/seed_web_link_emulator");
const projectId = process.env.GCLOUD_PROJECT || "demo-examcoach";
const functionsHost = process.env.FUNCTIONS_EMULATOR_HOST || "127.0.0.1:5001";
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099";

// Refuse to even instantiate an Admin connection outside the local emulator.
if (!projectId.startsWith("demo-") || !process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error("Web link tests require demo emulators.");
}
initializeApp({projectId});
const db = getFirestore();
const request = () => ({protocolVersion: 1, requestId: crypto.randomBytes(16).toString("hex"),
  tryoutId: "w2-synthetic", contentFingerprint: fixture.contentFingerprint});

async function account() {
  const r = await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`, {
    method: "POST", headers: {"content-type": "application/json"},
    body: JSON.stringify({email: `web-${crypto.randomUUID()}@example.com`, password: "test-password-123", returnSecureToken: true}),
  });
  assert.equal(r.status, 200);
  return r.json();
}
async function call(name, data, user) {
  const response = await fetch(`http://${functionsHost}/${projectId}/asia-southeast2/${name}`, {
    method: "POST", headers: {"content-type": "application/json", ...(user ? {authorization: `Bearer ${user.idToken}`} : {})},
    body: JSON.stringify({data}),
  });
  const body = await response.json();
  return {status: response.status, result: body.result ?? body.data, error: body.error};
}

test("W2 callable ownership, atomic replay, expiry, revocation and private storage", async () => {
  await seed(db);
  const [alice, bob] = await Promise.all([account(), account()]);
  for (const name of ["getWebMockLinkManagement", "createWebMockLink", "revokeWebMockLink"]) {
    assert.equal((await call(name, {protocolVersion: 1})).error.status, "UNAUTHENTICATED");
  }
  const canary = "W2_LOG_REDACTION_CANARY_DO_NOT_ECHO";
  const malformed = await call("createWebMockLink", {...request(), rawToken: canary}, alice);
  assert.equal(malformed.error.status, "INVALID_ARGUMENT");
  assert.ok(!JSON.stringify(malformed).includes(canary));
  const invalid = await call("createWebMockLink", {...request(), ownerUid: bob.localId}, alice);
  assert.equal(invalid.error.status, "INVALID_ARGUMENT");
  assert.equal((await call("createWebMockLink", {...request(), contentFingerprint: "a".repeat(64)}, alice)).error.status, "FAILED_PRECONDITION");
  const createRequest = request();
  const raced = await Promise.all([call("createWebMockLink", createRequest, alice), call("createWebMockLink", createRequest, alice)]);
  assert.ok(raced.every((r) => r.status === 200));
  assert.equal(raced.filter((r) => r.result.launchUrl !== null).length, 1);
  const issued = raced.find((r) => r.result.launchUrl !== null).result;
  const raw = new URL(issued.launchUrl).hash.slice(1);
  assert.match(raw, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(issued.link.expiresAtMs - issued.link.createdAtMs, TTL_MS);
  assert.ok(Math.abs(issued.serverNowMs - Date.now()) < 30000);
  const ref = db.collection("web_mock_links").doc(issued.link.linkId);
  const stored = (await ref.get()).data();
  assert.equal(stored.tokenHash, digest(raw));
  assert.equal(stored.ownerUid, alice.localId);
  assert.equal(stored.contentFingerprint, fixture.contentFingerprint);
  assert.match(stored.sessionId, /^[a-f0-9]{32}$/);
  assert.ok(!issued.launchUrl.includes(alice.localId));
  assert.ok(!issued.launchUrl.includes(stored.sessionId));
  assert.ok(!issued.launchUrl.includes(ref.id));
  assert.equal((await call("createWebMockLink", request(), alice)).error.status, "ALREADY_EXISTS");
  assert.equal((await call("createWebMockLink", {...createRequest, contentFingerprint: "b".repeat(64)}, alice)).error.status, "ALREADY_EXISTS");
  const managed = (await call("getWebMockLinkManagement", {protocolVersion: 1}, alice)).result;
  assert.equal(managed.links.length, 1);
  assert.equal(managed.tryouts[0].tryoutId, "w2-synthetic");
  assert.ok(!JSON.stringify(managed).includes(raw));
  assert.ok(!JSON.stringify(managed).includes(stored.tokenHash));
  assert.equal((await call("getWebMockLinkManagement", {protocolVersion: 1}, bob)).result.links.length, 0);
  const foreign = await call("revokeWebMockLink", {protocolVersion: 1, linkId: ref.id}, bob);
  const missing = await call("revokeWebMockLink", {protocolVersion: 1, linkId: "unknown"}, bob);
  assert.deepEqual(foreign, missing);
  assert.equal(foreign.error.status, "NOT_FOUND");
  const revokes = await Promise.all([1, 2].map(() => call("revokeWebMockLink", {protocolVersion: 1, linkId: ref.id}, alice)));
  assert.ok(revokes.every((r) => r.result.link.status === "revoked"));
  const replay = await call("createWebMockLink", createRequest, alice);
  assert.equal(replay.result.launchUrl, null);
  assert.equal(replay.result.link.status, "revoked");
  // Distinct requests must not create two active links, even when racing.
  const distinct = await Promise.all([call("createWebMockLink", request(), alice), call("createWebMockLink", request(), alice)]);
  assert.equal(distinct.filter((r) => r.status === 200).length, 1);
  assert.equal(distinct.find((r) => r.error).error.status, "ALREADY_EXISTS");
  const next = distinct.find((r) => r.result).result;
  assert.notEqual(next.launchUrl, issued.launchUrl);
  // Force only trusted emulator clock evidence, never client expiry fields.
  const expiredRef = db.collection("web_mock_links").doc(next.link.linkId);
  await expiredRef.update({expiresAt: Timestamp.fromMillis(Date.now() - 1)});
  assert.equal((await call("revokeWebMockLink", {protocolVersion: 1, linkId: expiredRef.id}, alice)).result.link.status, "expired");
  assert.equal((await expiredRef.get()).data().status, "expired");
  const newer = (await call("createWebMockLink", request(), alice)).result;
  assert.ok(newer.launchUrl);
  for (const status of ["completed", "timeout", "revoked", "expired"]) {
    await db.collection("web_mock_links").doc(newer.link.linkId).update({status});
    assert.equal((await call("revokeWebMockLink", {protocolVersion: 1, linkId: newer.link.linkId}, alice)).result.link.status, status);
  }
  const allLinks = await db.collection("web_mock_links").where("ownerUid", "==", alice.localId).get();
  const owner = db.collection("web_mock_owners").doc(alice.localId);
  const receipts = await owner.collection("create_requests").get();
  const persisted = JSON.stringify([allLinks.docs.map((s) => s.data()), (await owner.get()).data(), receipts.docs.map((s) => s.data())]);
  for (const token of [raw, new URL(next.launchUrl).hash.slice(1), new URL(newer.launchUrl).hash.slice(1)]) {
    assert.ok(!persisted.includes(token), "Raw token must not be persisted");
  }
  assert.equal((await db.collection("users").doc(alice.localId).collection("sessions").get()).size, 0);
  for (const name of ["firebase-debug.log", "firestore-debug.log"]) {
    const file = path.join(__dirname, "..", "..", name);
    if (fs.existsSync(file)) {
      const log = fs.readFileSync(file, "utf8");
      assert.ok(!log.includes(canary), "Request canary leaked to emulator logs");
      for (const token of [raw, new URL(next.launchUrl).hash.slice(1), new URL(newer.launchUrl).hash.slice(1)]) {
        assert.ok(!log.includes(token), "Response capability leaked to emulator logs");
      }
    }
  }
});

test("W2 rate limits include malformed attempts and bound new issuance", async () => {
  const user = await account();
  const service = new WebLinkService({database: db, enabled: () => true});
  for (let i = 0; i < 30; i++) {
    await assert.rejects(service.execute("create", user.localId, {rawToken: "never-log-this"}), {code: "invalid-argument"});
  }
  await assert.rejects(service.execute("create", user.localId, request()), {code: "resource-exhausted"});
  const owner = (await account()).localId;
  for (let i = 0; i < 6; i++) {
    const created = await service.execute("create", owner, request());
    await service.execute("revoke", owner, {protocolVersion: 1, linkId: created.link.linkId});
  }
  await assert.rejects(service.execute("create", owner, request()), {code: "resource-exhausted"});
  const readOwner = (await account()).localId;
  for (let i = 0; i < 60; i++) await service.execute("management", readOwner, {protocolVersion: 1});
  await assert.rejects(service.execute("management", readOwner, {protocolVersion: 1}), {code: "resource-exhausted"});
});
