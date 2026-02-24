/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp();
}
const db = admin.firestore();

// For cost control, you can set the maximum number of containers that can be
// running at the same time. This helps mitigate the impact of unexpected
// traffic spikes by instead downgrading performance. This limit is a
// per-function limit. You can override the limit for each function using the
// `maxInstances` option in the function's options, e.g.
// `onRequest({ maxInstances: 5 }, (req, res) => { ... })`.
// NOTE: setGlobalOptions does not apply to functions using the v1 API. V1
// functions should each use functions.runWith({ maxInstances: 10 }) instead.
// In the v1 API, each function can only serve one request per container, so
// this will be the maximum concurrent request count.
setGlobalOptions({ maxInstances: 10 });

// Create and deploy your first functions
// https://firebase.google.com/docs/functions/get-started

// exports.helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
// });

exports.submitDuelAttempt = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({error: "Method not allowed"});
    return;
  }

  const authHeader = req.get("Authorization") || "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.substring(7) : "";
  if (!token) {
    res.status(401).json({error: "Missing auth token"});
    return;
  }

  let decoded;
  try {
    decoded = await admin.auth().verifyIdToken(token);
  } catch (error) {
    res.status(401).json({error: "Invalid auth token"});
    return;
  }

  const uid = decoded.uid;
  const challengeId = String(req.body?.challengeId || "").trim();
  const metrics = req.body?.metrics || {};

  if (!challengeId) {
    res.status(400).json({error: "Missing challengeId"});
    return;
  }

  const intonationScore = clampInt(metrics.intonationScore, 0, 100);
  const rhythmScore = clampInt(metrics.rhythmScore, 0, 100);
  const consistencyScore = clampInt(metrics.consistencyScore, 0, 100);
  const noteCount = clampInt(metrics.noteCount, 0, 2000);
  const beatsAnalyzed = clampInt(metrics.beatsAnalyzed, 0, 2000);

  if (noteCount <= 0 || beatsAnalyzed <= 0) {
    res.status(400).json({error: "Metrics are incomplete"});
    return;
  }

  const derivedScore = computeDerivedScore(intonationScore, rhythmScore, consistencyScore);
  const challengeRef = db.collection("duelChallenges").doc(challengeId);
  const myAttemptRef = challengeRef.collection("attempts").doc(uid);

  try {
    const output = await db.runTransaction(async (txn) => {
      const challengeSnap = await txn.get(challengeRef);
      if (!challengeSnap.exists) {
        throw new Error("Challenge not found");
      }
      const challenge = challengeSnap.data() || {};

      const status = String(challenge.status || "");
      const participants = Array.isArray(challenge.participants) ? challenge.participants : [];
      const createdByUid = String(challenge.createdByUid || "");
      if (status !== "active" || participants.length !== 2 || !participants.includes(uid)) {
        throw new Error("Challenge is not active");
      }

      const opponentUid = participants.find((p) => p !== uid);
      if (!opponentUid) throw new Error("Missing opponent");

      const opponentAttemptRef = challengeRef.collection("attempts").doc(opponentUid);
      const opponentAttemptSnap = await txn.get(opponentAttemptRef);

      txn.set(myAttemptRef, {
        uid,
        intonationScore,
        rhythmScore,
        consistencyScore,
        noteCount,
        beatsAnalyzed,
        derivedScore,
        submittedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      if (!opponentAttemptSnap.exists) {
        txn.update(challengeRef, {
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return {finalized: false, derivedScore};
      }

      const opponentData = opponentAttemptSnap.data() || {};
      const opponentScore = clampInt(opponentData.derivedScore, 0, 100);

      const creatorScore = uid === createdByUid ? derivedScore : opponentScore;
      const otherScore = uid === createdByUid ? opponentScore : derivedScore;

      const creatorRef = db.collection("users").doc(createdByUid);
      const opponentRef = db.collection("users").doc(opponentUid);
      const creatorSnap = await txn.get(creatorRef);
      const opponentSnap = await txn.get(opponentRef);

      const creatorRating = clampInt(creatorSnap.data()?.duelRating, 800, 5000, 1000);
      const opponentRating = clampInt(opponentSnap.data()?.duelRating, 800, 5000, 1000);

      const creatorOutcome = creatorScore > otherScore ? 1 : (creatorScore < otherScore ? 0 : 0.5);
      const opponentOutcome = 1 - creatorOutcome;
      const winnerUid = creatorScore === otherScore ? null : (creatorScore > otherScore ? createdByUid : opponentUid);

      const creatorExpected = 1 / (1 + Math.pow(10, (opponentRating - creatorRating) / 400));
      const opponentExpected = 1 / (1 + Math.pow(10, (creatorRating - opponentRating) / 400));
      const k = 24;
      const creatorDelta = Math.round(k * (creatorOutcome - creatorExpected));
      const opponentDelta = Math.round(k * (opponentOutcome - opponentExpected));
      const creatorNewRating = Math.max(800, creatorRating + creatorDelta);
      const opponentNewRating = Math.max(800, opponentRating + opponentDelta);

      const seasonKey = currentSeasonKey();
      applyUserResult(txn, creatorRef, creatorSnap.data() || {}, creatorOutcome, creatorNewRating, creatorDelta, seasonKey);
      applyUserResult(txn, opponentRef, opponentSnap.data() || {}, opponentOutcome, opponentNewRating, opponentDelta, seasonKey);

      txn.update(challengeRef, {
        status: "completed",
        winnerUid: winnerUid,
        creatorScore: creatorScore,
        opponentScore: otherScore,
        creatorRatingDelta: creatorDelta,
        opponentRatingDelta: opponentDelta,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {finalized: true, derivedScore, creatorScore, opponentScore: otherScore};
    });

    res.status(200).json({ok: true, ...output});
  } catch (error) {
    logger.error("submitDuelAttempt failed", error);
    res.status(400).json({error: String(error.message || error)});
  }
});

function computeDerivedScore(intonationScore, rhythmScore, consistencyScore) {
  const weighted = (intonationScore * 0.5) + (rhythmScore * 0.35) + (consistencyScore * 0.15);
  return clampInt(Math.round(weighted), 0, 100);
}

function currentSeasonKey() {
  const now = new Date();
  const utc = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  const day = utc.getUTCDay() || 7; // ISO Monday=1..Sunday=7
  utc.setUTCDate(utc.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(utc.getUTCFullYear(), 0, 1));
  const week = Math.ceil((((utc - yearStart) / 86400000) + 1) / 7);
  return `${utc.getUTCFullYear()}-W${week}`;
}

function applyUserResult(txn, userRef, current, outcome, newRating, ratingDelta, seasonKey) {
  const wins = clampInt(current.duelWins, 0, 100000, 0) + (outcome === 1 ? 1 : 0);
  const losses = clampInt(current.duelLosses, 0, 100000, 0) + (outcome === 0 ? 1 : 0);
  const draws = clampInt(current.duelDraws, 0, 100000, 0) + (outcome === 0.5 ? 1 : 0);

  const currentSeason = String(current.duelSeasonKey || "");
  const reset = currentSeason !== seasonKey;
  const oldSeasonPoints = reset ? 0 : clampInt(current.duelSeasonPoints, 0, 100000, 0);
  const oldSeasonMatches = reset ? 0 : clampInt(current.duelSeasonMatches, 0, 100000, 0);
  const oldSeasonWins = reset ? 0 : clampInt(current.duelSeasonWins, 0, 100000, 0);
  const oldSeasonRatingDelta = reset ? 0 : clampInt(current.duelSeasonRatingDelta, -100000, 100000, 0);

  const seasonPoints = oldSeasonPoints + (outcome === 1 ? 3 : (outcome === 0.5 ? 1 : 0));
  const seasonMatches = oldSeasonMatches + 1;
  const seasonWins = oldSeasonWins + (outcome === 1 ? 1 : 0);
  const seasonRatingDelta = oldSeasonRatingDelta + ratingDelta;

  txn.set(userRef, {
    duelRating: newRating,
    duelLeague: duelLeagueForRating(newRating),
    duelWins: wins,
    duelLosses: losses,
    duelDraws: draws,
    duelSeasonKey: seasonKey,
    duelSeasonPoints: seasonPoints,
    duelSeasonMatches: seasonMatches,
    duelSeasonWins: seasonWins,
    duelSeasonRatingDelta: seasonRatingDelta,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}

function duelLeagueForRating(rating) {
  if (rating >= 1300) return "gold";
  if (rating >= 1150) return "silver";
  return "bronze";
}

function clampInt(value, min, max, fallback = min) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, Math.round(n)));
}
