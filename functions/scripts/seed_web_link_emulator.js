"use strict";

const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const crypto = require("node:crypto");

// This manifest is not a question pack and makes no publication claim.
const fixture = Object.freeze({
  title: "Simulasi link lokal — bukan materi ujian",
  contentFingerprint: crypto.createHash("sha256").update("examcoach:w2:synthetic-manifest:v1").digest("hex"),
  validationStatus: "emulator_fixture", emulatorFixture: true,
  questionCount: 6, durationSeconds: 360,
});

async function seed(database) {
  await database.collection("web_mock_tryouts").doc("w2-synthetic").set(fixture);
}

if (require.main === module) {
  if (!/^demo-[a-z0-9-]+$/.test(process.env.GCLOUD_PROJECT || "") ||
      !/^(127\.0\.0\.1|localhost):[0-9]+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) {
    throw new Error("Seed requires a demo project and local Firestore emulator.");
  }
  initializeApp({projectId: process.env.GCLOUD_PROJECT});
  seed(getFirestore()).then(() => {
    console.log("Synthetic W2 manifest seeded in the local emulator.");
  }).catch(() => {
    console.error("Local W2 seed failed.");
    process.exitCode = 1;
  });
}
module.exports = {fixture, seed};
