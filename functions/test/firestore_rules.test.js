"use strict";

const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc} = require("firebase/firestore");

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

    await assertSucceeds(getDoc(aliceSession));
    await assertFails(getDoc(doc(bob, "users/alice/sessions/s1")));
    await assertFails(getDoc(doc(guest, "users/alice/sessions/s1")));
    await assertFails(setDoc(aliceSession, {status: "completed"}));
    await assertSucceeds(
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
