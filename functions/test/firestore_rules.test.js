"use strict";

const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {collection, deleteDoc, doc, getDoc, getDocs, setDoc, updateDoc} = require("firebase/firestore");

test("Firestore rules isolate user data and deny client writes", async () => {
  const environment = await initializeTestEnvironment({
    projectId: "demo-examcoach-rules",
    firestore: {
      rules: fs.readFileSync(
        path.join(__dirname, "..", "..", "firestore.rules"),
        "utf8",
      ),
    },
  });
  try {
    await environment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "users/alice/sessions/s1"), {
        status: "active",
      });
      await setDoc(doc(context.firestore(), "users/alice/ai_insights/i1"), {
        summary: "Server-generated insight",
      });
      await setDoc(doc(context.firestore(), "config/ai_coach_policy"), {
        enabled: true,
      });
      await setDoc(
        doc(context.firestore(), "published_question_packs/published-pack"),
        {validation_status: "published"},
      );
      await setDoc(
        doc(context.firestore(), "published_question_packs/draft-pack"),
        {validation_status: "draft"},
      );
    });
    const alice = environment.authenticatedContext("alice").firestore();
    const bob = environment.authenticatedContext("bob").firestore();
    const guest = environment.unauthenticatedContext().firestore();
    const aliceSession = doc(alice, "users/alice/sessions/s1");
    const paths = [
      "web_mock_links/l1", "web_mock_tryouts/t1", "web_mock_owners/alice",
      "web_mock_owners/alice/create_requests/r1", "web_mock_owners/alice/rate_limits/mutation",
      "web_mock_links/missing/answers/a1",
      "published_question_packs/published-pack",
    ];
    await environment.withSecurityRulesDisabled(async (context) => {
      for (const path of paths) await setDoc(doc(context.firestore(), path), {
        ownerUid: "alice", tokenHash: "hash", status: "active", validation_status: "published",
        correct_option_id: "b", explanation: "Answer key must remain private",
      });
    });
    // Guest, owner, other owner, and a client asserting admin cannot bypass
    // the Admin-only boundary. Include orphaned descendants and list queries.
    for (const client of [guest, alice, bob, environment.authenticatedContext("admin", {admin: true}).firestore()]) {
      for (const path of paths) {
        const ref = doc(client, path);
        await assertFails(getDoc(ref));
        await assertFails(getDocs(collection(client, path.split("/").slice(0, -1).join("/"))));
        await assertFails(setDoc(doc(client, `${path}-new`), {ownerUid: "bob", role: "admin"}));
        await assertFails(updateDoc(ref, {ownerUid: "bob", status: "completed", expiresAt: "future"}));
        await assertFails(deleteDoc(ref));
      }
    }
    for (const payload of [
      {}, {ownerUid: 12}, {createdAt: -1, expiresAt: Number.MAX_SAFE_INTEGER},
      {tokenHash: "x".repeat(200000)}, {extraData: true}, {role: "admin"},
      {status: "active", sessionId: "../../users/bob"}, {count: 1000000},
    ]) {
      await assertFails(setDoc(doc(alice, "web_mock_links/invalid-create"), payload));
      await assertFails(setDoc(doc(alice, "web_mock_links/l1"), payload));
      if (Object.keys(payload).length) await assertFails(updateDoc(doc(alice, "web_mock_links/l1"), payload));
    }
    await assertFails(setDoc(doc(alice, "users/alice"), {role: "admin"}));
    await assertFails(getDocs(collection(guest, "users")));


    await assertSucceeds(getDoc(aliceSession));
    await assertFails(getDoc(doc(bob, "users/alice/sessions/s1")));
    await assertFails(getDoc(doc(guest, "users/alice/sessions/s1")));
    await assertFails(setDoc(aliceSession, {status: "completed"}));
    await assertSucceeds(
      getDoc(doc(alice, "users/alice/ai_insights/i1")),
    );
    await assertFails(getDoc(doc(bob, "users/alice/ai_insights/i1")));
    await assertFails(
      setDoc(doc(alice, "users/alice/ai_insights/i2"), {
        summary: "Forged client insight",
      }),
    );
    await assertFails(getDoc(doc(alice, "config/ai_coach_policy")));
    await assertFails(
      getDoc(doc(guest, "published_question_packs/published-pack")),
    );
    await assertFails(
      getDoc(doc(guest, "published_question_packs/draft-pack")),
    );
    await assertFails(
      setDoc(doc(alice, "published_question_packs/client-pack"), {
        validation_status: "published",
      }),
    );
  } finally {
    await environment.cleanup();
  }
});
