"use strict";

const crypto = require("node:crypto");
const {Timestamp} = require("firebase-admin/firestore");
const TTL_MS = 12 * 60 * 60 * 1000;
const TERMINAL = new Set(["expired", "revoked", "completed", "timeout"]);
const ID = /^[A-Za-z0-9_-]{1,80}$/;
const FINGERPRINT = /^[a-f0-9]{64}$/;

class WebLinkError extends Error {
  constructor(code) {
    // Never interpolate requests, SDK errors or capability material.
    super(`Web link request: ${code}`);
    this.code = code;
  }
}

function matches(pattern, value) {
  return typeof value === "string" && pattern.exec(value)?.[0] === value;
}

function emulatorEnabled(env = process.env) {
  return env.FUNCTIONS_EMULATOR === "true" &&
    env.EXAMCOACH_WEB_LINKS_ENABLED === "true" &&
    matches(/^demo-[a-z0-9-]+$/, env.GCLOUD_PROJECT) &&
    matches(/^(127\.0\.0\.1|localhost):[0-9]+$/, env.FIRESTORE_EMULATOR_HOST);
}

function validateRequest(data, fields) {
  if (!data || typeof data !== "object" || Array.isArray(data) ||
      data.protocolVersion !== 1 ||
      Object.keys(data).length !== fields.length + 1 ||
      Object.keys(data).some((key) => !["protocolVersion", ...fields].includes(key))) {
    throw new WebLinkError("invalid-argument");
  }
  for (const field of fields) {
    const pattern = field === "contentFingerprint" ? FINGERPRINT :
      field === "requestId" ? /^[A-Za-z0-9_-]{22,80}$/ : ID;
    if (!matches(pattern, data[field])) {
      throw new WebLinkError("invalid-argument");
    }
  }
  return data;
}

function digest(value) {
  return crypto.createHash("sha256").update(`examcoach:web-link:v1:${value}`).digest("hex");
}

function capability() {
  const raw = crypto.randomBytes(32).toString("base64url");
  return {raw, hash: digest(raw)};
}

function currentStatus(link, now) {
  if (TERMINAL.has(link.status)) return link.status;
  if (!["active", "claimed"].includes(link.status)) throw new WebLinkError("failed-precondition");
  return now >= link.expiresAt.toMillis() ? "expired" : link.status;
}

function summary(id, link, now) {
  return {
    linkId: id, tryoutId: link.tryoutId,
    contentFingerprint: link.contentFingerprint,
    status: currentStatus(link, now),
    createdAtMs: link.createdAt.toMillis(), expiresAtMs: link.expiresAt.toMillis(),
  };
}

function manifest(id, data) {
  // W2 accepts only explicitly synthetic emulator content. Real publication and
  // immutable pack loading must be implemented with the W3 question projection.
  if (!matches(ID, id) || !data || data.validationStatus !== "emulator_fixture" ||
      data.emulatorFixture !== true || typeof data.title !== "string" ||
      data.title.length < 1 || data.title.length > 120 ||
      !matches(FINGERPRINT, data.contentFingerprint) ||
      !Number.isInteger(data.questionCount) || data.questionCount < 1 || data.questionCount > 500 ||
      !Number.isInteger(data.durationSeconds) || data.durationSeconds < 60 || data.durationSeconds > 14400) {
    return null;
  }
  return {tryoutId: id, title: data.title, contentFingerprint: data.contentFingerprint,
    questionCount: data.questionCount, durationSeconds: data.durationSeconds};
}

class WebLinkService {
  constructor({database, clock = Date.now, enabled = emulatorEnabled}) {
    this.db = database;
    this.clock = clock;
    this.enabled = enabled;
  }

  async execute(action, uid, data) {
    if (typeof uid !== "string" || !uid) throw new WebLinkError("unauthenticated");
    if (!this.enabled()) throw new WebLinkError("unavailable");
    // Count malformed/rejected attempts as well as successes, before validation.
    await this.rateLimit(uid, action === "management" ? "read" : "mutation");
    if (action === "management") {
      validateRequest(data, []);
      return this.management(uid);
    }
    if (action === "create") {
      validateRequest(data, ["requestId", "tryoutId", "contentFingerprint"]);
      return this.create(uid, data);
    }
    if (action === "revoke") {
      validateRequest(data, ["linkId"]);
      return this.revoke(uid, data.linkId);
    }
    throw new WebLinkError("invalid-argument");
  }

  owner(uid) { return this.db.collection("web_mock_owners").doc(uid); }
  link(id) { return this.db.collection("web_mock_links").doc(id); }

  async rateLimit(uid, bucket) {
    const ref = this.owner(uid).collection("rate_limits").doc(bucket);
    await this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const now = this.clock();
      const previous = snap.data();
      const fresh = !previous || now >= previous.startMs + 60000;
      const count = fresh ? 0 : previous.count;
      if (count >= (bucket === "read" ? 60 : 30)) throw new WebLinkError("resource-exhausted");
      tx.set(ref, {startMs: fresh ? now : previous.startMs, count: count + 1});
    });
  }

  async management(uid) {
    const ownerRef = this.owner(uid);
    // A transaction gives the mobile client one consistent latest-link view.
    return this.db.runTransaction(async (tx) => {
      const owner = (await tx.get(ownerRef)).data();
      const catalog = await tx.get(this.db.collection("web_mock_tryouts").limit(20));
      const ids = Object.values(owner?.slots || {});
      const links = [];
      for (const id of ids) {
        const snap = await tx.get(this.link(id));
        if (!snap.exists || snap.data().ownerUid !== uid) throw new WebLinkError("failed-precondition");
        links.push(snap);
      }
      const now = this.clock();
      for (const snap of links) this.persistExpiry(tx, snap, now);
      return {protocolVersion: 1, serverNowMs: now,
        tryouts: catalog.docs.map((s) => manifest(s.id, s.data())).filter(Boolean),
        links: links.map((s) => summary(s.id, s.data(), now))};
    });
  }

  async create(uid, data) {
    const ownerRef = this.owner(uid);
    const requestRef = ownerRef.collection("create_requests").doc(digest(data.requestId));
    const secret = capability();
    const linkId = crypto.randomBytes(16).toString("hex");
    const sessionId = crypto.randomBytes(16).toString("hex");
    return this.db.runTransaction(async (tx) => {
      const receipt = (await tx.get(requestRef)).data();
      if (receipt) {
        if (receipt.tryoutId !== data.tryoutId || receipt.contentFingerprint !== data.contentFingerprint) {
          throw new WebLinkError("already-exists");
        }
        const snap = await tx.get(this.link(receipt.linkId));
        if (!snap.exists || snap.data().ownerUid !== uid) throw new WebLinkError("failed-precondition");
        const now = this.clock();
        this.persistExpiry(tx, snap, now);
        return {protocolVersion: 1, serverNowMs: now, link: summary(snap.id, snap.data(), now), launchUrl: null};
      }
      const owner = (await tx.get(ownerRef)).data() || {};
      const source = await tx.get(this.db.collection("web_mock_tryouts").doc(data.tryoutId));
      const selected = manifest(source.id, source.data());
      if (!selected || selected.contentFingerprint !== data.contentFingerprint) {
        throw new WebLinkError("failed-precondition");
      }
      const slots = owner.slots || {};
      const previousId = Object.hasOwn(slots, data.tryoutId) ? slots[data.tryoutId] : null;
      const previous = previousId ? await tx.get(this.link(previousId)) : null;
      const now = this.clock();
      if (previous && (!previous.exists || previous.data().ownerUid !== uid ||
          !TERMINAL.has(currentStatus(previous.data(), now)))) {
        throw new WebLinkError("already-exists");
      }
      if (!previousId && Object.keys(slots).length >= 20) throw new WebLinkError("resource-exhausted");
      const freshHour = !owner.createWindowStartMs || now >= owner.createWindowStartMs + 3600000;
      const created = freshHour ? 0 : owner.createCount;
      if (created >= 6) throw new WebLinkError("resource-exhausted");
      const record = {ownerUid: uid, tryoutId: data.tryoutId,
        contentFingerprint: data.contentFingerprint, sessionId, tokenHash: secret.hash,
        status: "active", createdAt: Timestamp.fromMillis(now), expiresAt: Timestamp.fromMillis(now + TTL_MS)};
      if (previous) this.persistExpiry(tx, previous, now);
      tx.create(this.link(linkId), record);
      tx.create(requestRef, {linkId, tryoutId: data.tryoutId, contentFingerprint: data.contentFingerprint});
      tx.set(ownerRef, {slots: {...slots, [data.tryoutId]: linkId},
        createWindowStartMs: freshHour ? now : owner.createWindowStartMs, createCount: created + 1});
      // Fixed loopback URL; never accept a client origin or serialize IDs into it.
      return {protocolVersion: 1, serverNowMs: now, link: summary(linkId, record, now),
        launchUrl: `http://127.0.0.1:5173/mock-test#${secret.raw}`};
    });
  }

  async revoke(uid, id) {
    return this.db.runTransaction(async (tx) => {
      const snap = await tx.get(this.link(id));
      // Same result for missing and foreign records; no ownership oracle.
      if (!snap.exists || snap.data().ownerUid !== uid) throw new WebLinkError("not-found");
      const record = snap.data();
      const now = this.clock();
      const status = currentStatus(record, now);
      if (TERMINAL.has(status)) {
        this.persistExpiry(tx, snap, now);
        return {protocolVersion: 1, serverNowMs: now, link: summary(id, record, now)};
      }
      tx.update(snap.ref, {status: "revoked", revokedAt: Timestamp.fromMillis(now)});
      return {protocolVersion: 1, serverNowMs: now, link: summary(id, {...record, status: "revoked"}, now)};
    });
  }

  persistExpiry(tx, snap, now) {
    if (currentStatus(snap.data(), now) === "expired" && snap.data().status !== "expired") {
      tx.update(snap.ref, {status: "expired"});
    }
  }
}

module.exports = {WebLinkService, WebLinkError, TTL_MS, capability, digest,
  currentStatus, validateRequest, emulatorEnabled, manifest};
