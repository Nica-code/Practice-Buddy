const functions = require("firebase-functions");
const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp();
}

setGlobalOptions({maxInstances: 10});

const db = admin.firestore();

const OPEN_MATCH_FALLBACK_SECONDS = 30;
const ACCEPT_WINDOW_SECONDS = 24 * 60 * 60;
const SUBMISSION_WINDOW_SECONDS = 24 * 60 * 60;
const SUBMISSION_SETTLE_GRACE_SECONDS = 30;
const MAX_PENDING_INVITES_PER_USER = 5;
const SERVER_TRIAL_DAYS = 7;
const PRO_SUBSCRIPTION_PRODUCT_IDS = new Set([
  "practicebuddy.pro.monthly",
]);

const ROUTE_PLAY_DUEL = "play_duel";
const ROUTE_SOCIAL_FRIEND_REQUESTS = "social_friend_requests";
const ROUTE_SOCIAL_CHAT = "social_chat";
const TYPE_DUEL = "duel";
const TYPE_FRIEND_REQUEST = "friend_request";
const TYPE_CHAT_MESSAGE = "chat_message";

exports.syncEntitlements = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({error: "Method not allowed"});
    return;
  }

  try {
    const uid = await requireUID(req);
    const requestTrial = req.body?.requestTrial === true;
    const activeProductIDs = sanitizeActiveProductIDs(req.body?.activeProductIDs);
    const nowMs = Date.now();

    const result = await db.runTransaction(async (txn) => {
      const userRef = db.collection("users").doc(uid);
      const userSnap = await txn.get(userRef);
      const userData = userSnap.data() || {};

      const existingIsMaster = userData.isMasterAccount === true;
      const existingTrialUsed = userData.trialUsed === true;
      let trialStartedAt = userData.trialStartedAt?.toDate ? userData.trialStartedAt.toDate() : null;
      let trialEndsAt = userData.trialEndsAt?.toDate ? userData.trialEndsAt.toDate() : null;
      let trialUsed = existingTrialUsed || !!trialStartedAt || !!trialEndsAt;
      let trialStartedNow = false;

      if (requestTrial && !trialUsed) {
        trialStartedAt = new Date(nowMs);
        trialEndsAt = new Date(nowMs + (SERVER_TRIAL_DAYS * 24 * 60 * 60 * 1000));
        trialUsed = true;
        trialStartedNow = true;
      }

      const trialActive = !!trialEndsAt && trialEndsAt.getTime() > nowMs;
      const subscriptionActive = activeProductIDs.length > 0;

      let entitlementTier = "free";
      if (existingIsMaster) {
        entitlementTier = "all_access";
      } else if (subscriptionActive || trialActive) {
        entitlementTier = "pro";
      }
      const isPro = entitlementTier !== "free";

      const payload = {
        subscriptionActive,
        subscriptionProductIDs: activeProductIDs,
        entitlementTier,
        isPro,
        trialUsed,
        trialStartedAt: trialStartedAt ? admin.firestore.Timestamp.fromDate(trialStartedAt) : null,
        trialEndsAt: trialEndsAt ? admin.firestore.Timestamp.fromDate(trialEndsAt) : null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (isPro && !userData.proSince) {
        payload.proSince = admin.firestore.FieldValue.serverTimestamp();
      }

      txn.set(userRef, payload, {merge: true});

      return {
        uid,
        entitlementTier,
        isPro,
        subscriptionActive,
        subscriptionProductIDs: activeProductIDs,
        trialUsed,
        trialActive,
        trialStartedNow,
        trialStartedAtMs: trialStartedAt ? trialStartedAt.getTime() : null,
        trialEndsAtMs: trialEndsAt ? trialEndsAt.getTime() : null,
        trialSecondsRemaining: trialEndsAt ? Math.max(0, Math.floor((trialEndsAt.getTime() - nowMs) / 1000)) : 0,
      };
    });

    res.status(200).json({ok: true, ...result});
  } catch (error) {
    logger.error("syncEntitlements failed", error);
    res.status(400).json({error: String(error.message || error)});
  }
});

exports.pushTestNotification = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({error: "Method not allowed"});
    return;
  }

  try {
    const uid = await requireUID(req);
    const route = String(req.body?.route || ROUTE_SOCIAL_CHAT).trim().toLowerCase();
    let data = {
      pb_route: ROUTE_SOCIAL_CHAT,
      pb_type: TYPE_CHAT_MESSAGE,
    };
    let category = "pb.message";
    let prefKey = "notificationMessages";
    let title = "Test Notification";
    let body = "Push notifications are configured correctly.";

    if (route === ROUTE_PLAY_DUEL) {
      data = {
        pb_route: ROUTE_PLAY_DUEL,
        pb_type: TYPE_DUEL,
        challengeId: String(req.body?.challengeId || ""),
      };
      category = "pb.duel";
      prefKey = "notificationDuels";
      title = "Test Duel Notification";
      body = "Open Play to verify duel deep-link routing.";
    } else if (route === ROUTE_SOCIAL_FRIEND_REQUESTS) {
      data = {
        pb_route: ROUTE_SOCIAL_FRIEND_REQUESTS,
        pb_type: TYPE_FRIEND_REQUEST,
      };
      category = "pb.friend_request";
      prefKey = "notificationFriendRequests";
      title = "Test Friend Request Notification";
      body = "Open Social to verify friend-request routing.";
    }

    await safePushToUser(uid, {title, body, prefKey, data, category});
    res.status(200).json({ok: true});
  } catch (error) {
    logger.error("pushTestNotification failed", error);
    res.status(400).json({error: String(error.message || error)});
  }
});

exports.duelQueueJoin = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({error: "Method not allowed"});
    return;
  }

  try {
    const uid = await requireUID(req);
    const requestedOctaves = parseOctaves(req.body?.octaves);
    const requesterSnap = await db.collection("users").doc(uid).get();
    const requesterRating = clampInt(requesterSnap.data()?.duelRating, 0, 1000000, 0);
    const requesterDisplayName = String(requesterSnap.data()?.displayName || "").trim() || "Player";
    const requesterRequirement = duelRequirementForRating(requesterRating);
    const octaves = Math.max(requestedOctaves, requesterRequirement.octaves);

    await settleExpiredForUser(uid);

    const output = await db.runTransaction(async (txn) => {
      const existingOpen = await txn.get(db.collection("duelChallenges")
          .where("createdByUid", "==", uid)
          .where("status", "==", "open")
          .limit(1));
      if (!existingOpen.empty) {
        return {status: "already_queued", challengeId: existingOpen.docs[0].id};
      }

      const activeMine = await txn.get(db.collection("duelChallenges")
          .where("participants", "array-contains", uid)
          .where("status", "==", "active")
          .limit(1));
      if (!activeMine.empty) {
        return {status: "blocked_active_duel"};
      }

      const openRows = await txn.get(db.collection("duelChallenges")
          .where("status", "==", "open")
          .limit(40));

      const now = Date.now();
      const candidates = [];
      for (const doc of openRows.docs) {
        const data = doc.data() || {};
        const creatorUID = String(data.createdByUid || "");
        if (!creatorUID || creatorUID === uid) continue;
        const candidateOctaves = parseOctaves(data.octaveCount);
        const createdAt = data.createdAt?.toDate ? data.createdAt.toDate().getTime() : now;
        const ageSec = Math.max(0, Math.floor((now - createdAt) / 1000));
        const strict = candidateOctaves === octaves;
        const fallback = !strict && ageSec >= OPEN_MATCH_FALLBACK_SECONDS;
        if (!strict && !fallback) continue;
        candidates.push({
          doc,
          creatorUID,
          candidateOctaves,
          priority: strict ? 0 : 1,
          ageSec,
        });
      }

      candidates.sort((a, b) => (a.priority - b.priority) || (b.ageSec - a.ageSec));
      if (candidates.length > 0) {
        const match = candidates[0];
        const ref = match.doc.ref;
        const latest = await txn.get(ref);
        const latestData = latest.data() || {};
        if (!latest.exists || latestData.status !== "open") {
          return {status: "retry"};
        }
        const creatorUID = String(latestData.createdByUid || "");
        if (!creatorUID || creatorUID === uid) {
          return {status: "retry"};
        }
        const creatorOctaves = parseOctaves(latestData.octaveCount);
        const creatorSnap = await txn.get(db.collection("users").doc(creatorUID));
        const creatorRating = clampInt(creatorSnap.data()?.duelRating, 0, 1000000, 0);
        const creatorDisplayName = String(creatorSnap.data()?.displayName || "").trim() || "Player";
        const creatorRequirement = duelRequirementForRating(creatorRating);
        const matchRequirement = maxDuelRequirement(creatorRequirement, requesterRequirement);
        const matchOctaves = Math.max(creatorOctaves, matchRequirement.octaves);

        txn.update(ref, {
          status: "invited",
          queueType: "open",
          opponentUid: uid,
          participants: [creatorUID, uid],
          creatorAccepted: true,
          opponentAccepted: false,
          opponentRequestedOctaves: octaves,
          createdByDisplayName: creatorDisplayName,
          opponentDisplayName: requesterDisplayName,
          octaveCount: matchOctaves,
          requiredLeague: matchRequirement.league,
          requiredMinTempoBPM: matchRequirement.minTempoBPM,
          objective: "Match found • awaiting acceptance",
          matchFoundAt: admin.firestore.FieldValue.serverTimestamp(),
          acceptByAt: admin.firestore.Timestamp.fromMillis(now + (ACCEPT_WINDOW_SECONDS * 1000)),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return {
          status: "matched_pending_accept",
          challengeId: ref.id,
          octaves: matchOctaves,
          requiredLeague: matchRequirement.league,
          requiredMinTempoBPM: matchRequirement.minTempoBPM,
          notifyUid: creatorUID,
        };
      }

      const ref = db.collection("duelChallenges").doc();
      txn.set(ref, {
        createdByUid: uid,
        createdByDisplayName: requesterDisplayName,
        opponentUid: null,
        opponentDisplayName: null,
        participants: [uid],
        status: "open",
        queueType: "open",
        objective: duelObjective("Queued", octaves, requesterRequirement.minTempoBPM),
        scaleName: null,
        octaveCount: octaves,
        requiredLeague: requesterRequirement.league,
        requiredMinTempoBPM: requesterRequirement.minTempoBPM,
        creatorAccepted: true,
        opponentAccepted: false,
        opponentRequestedOctaves: null,
        creatorScore: null,
        opponentScore: null,
        winnerUid: null,
        creatorRatingDelta: 0,
        opponentRatingDelta: 0,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        startedAt: null,
        submissionDeadlineAt: null,
        completedAt: null,
      });
      return {
        status: "queued",
        challengeId: ref.id,
        octaves,
        requiredLeague: requesterRequirement.league,
        requiredMinTempoBPM: requesterRequirement.minTempoBPM,
      };
    });

    if (output.status === "matched_pending_accept" && output.notifyUid) {
      await safePushToUser(output.notifyUid, {
        title: "Duel Match Found",
        body: "A queued duel is ready. Accept to start.",
        prefKey: "notificationDuels",
        data: {
          pb_route: ROUTE_PLAY_DUEL,
          pb_type: TYPE_DUEL,
          challengeId: String(output.challengeId || ""),
        },
        category: "pb.duel",
      });
    }

    res.status(200).json({ok: true, ...output});
  } catch (error) {
    logger.error("duelQueueJoin failed", error);
    res.status(400).json({error: String(error.message || error)});
  }
});

exports.duelQueueCancel = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({error: "Method not allowed"});
    return;
  }

  try {
    const uid = await requireUID(req);
    const openRows = await db.collection("duelChallenges")
        .where("createdByUid", "==", uid)
        .where("status", "==", "open")
        .limit(1)
        .get();
    if (openRows.empty) {
      res.status(200).json({ok: true, status: "nothing_to_cancel"});
      return;
    }
    await openRows.docs[0].ref.set({
      status: "canceled",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    res.status(200).json({ok: true, status: "canceled"});
  } catch (error) {
    logger.error("duelQueueCancel failed", error);
    res.status(400).json({error: String(error.message || error)});
  }
});

exports.duelInvite = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({error: "Method not allowed"});
    return;
  }

  try {
    const uid = await requireUID(req);
    const targetUID = String(req.body?.targetUID || "").trim();
    const source = parseInviteSource(req.body?.source);
    const requestedOctaves = parseOctaves(req.body?.octaves);
    if (!targetUID || targetUID === uid) {
      throw new Error("Invalid target");
    }

    const [senderSnap, targetSnap] = await Promise.all([
      db.collection("users").doc(uid).get(),
      db.collection("users").doc(targetUID).get(),
    ]);
    const senderDisplayName = String(senderSnap.data()?.displayName || "").trim() || "Player";
    const targetDisplayName = String(targetSnap.data()?.displayName || "").trim() || "Player";
    const senderRequirement = duelRequirementForRating(clampInt(senderSnap.data()?.duelRating, 0, 1000000, 0));
    const targetRequirement = duelRequirementForRating(clampInt(targetSnap.data()?.duelRating, 0, 1000000, 0));
    const matchRequirement = maxDuelRequirement(senderRequirement, targetRequirement);
    const octaves = Math.max(requestedOctaves, matchRequirement.octaves);

    await settleExpiredForUser(uid);
    await settleExpiredForUser(targetUID);

    const pendingForPairOutbound = await db.collection("duelChallenges")
        .where("createdByUid", "==", uid)
        .where("opponentUid", "==", targetUID)
        .where("status", "==", "invited")
        .limit(1)
        .get();
    if (!pendingForPairOutbound.empty) {
      throw new Error("You already have a pending duel with this user.");
    }

    const pendingForPairInbound = await db.collection("duelChallenges")
        .where("createdByUid", "==", targetUID)
        .where("opponentUid", "==", uid)
        .where("status", "==", "invited")
        .limit(1)
        .get();
    if (!pendingForPairInbound.empty) {
      throw new Error("This user already has a pending duel with you.");
    }

    const senderPending = await db.collection("duelChallenges")
        .where("participants", "array-contains", uid)
        .where("status", "==", "invited")
        .limit(MAX_PENDING_INVITES_PER_USER + 1)
        .get();
    if (senderPending.size >= MAX_PENDING_INVITES_PER_USER) {
      throw new Error("You reached the pending duel limit. Resolve existing invites first.");
    }

    const targetPending = await db.collection("duelChallenges")
        .where("participants", "array-contains", targetUID)
        .where("status", "==", "invited")
        .limit(MAX_PENDING_INVITES_PER_USER + 1)
        .get();
    if (targetPending.size >= MAX_PENDING_INVITES_PER_USER) {
      throw new Error("Target user reached the pending duel limit.");
    }

    const senderActive = await db.collection("duelChallenges")
        .where("participants", "array-contains", uid)
        .where("status", "==", "active")
        .limit(1)
        .get();
    if (!senderActive.empty) {
      throw new Error("Finish your active duel before sending a new invitation.");
    }

    const targetActive = await db.collection("duelChallenges")
        .where("participants", "array-contains", targetUID)
        .where("status", "==", "active")
        .limit(1)
        .get();
    if (!targetActive.empty) {
      throw new Error("Target user is currently in an active duel.");
    }

    const ref = db.collection("duelChallenges").doc();
    await ref.set({
      createdByUid: uid,
      createdByDisplayName: senderDisplayName,
      opponentUid: targetUID,
      opponentDisplayName: targetDisplayName,
      participants: [uid, targetUID],
      status: "invited",
      queueType: source,
      objective: duelObjective("Challenge", octaves, matchRequirement.minTempoBPM),
      scaleName: null,
      octaveCount: octaves,
      requiredLeague: matchRequirement.league,
      requiredMinTempoBPM: matchRequirement.minTempoBPM,
      creatorAccepted: true,
      opponentAccepted: false,
      opponentRequestedOctaves: null,
      creatorScore: null,
      opponentScore: null,
      winnerUid: null,
      creatorRatingDelta: 0,
      opponentRatingDelta: 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      startedAt: null,
      submissionDeadlineAt: null,
      completedAt: null,
      matchFoundAt: admin.firestore.FieldValue.serverTimestamp(),
      acceptByAt: admin.firestore.Timestamp.fromMillis(Date.now() + (ACCEPT_WINDOW_SECONDS * 1000)),
    });

    await safePushToUser(targetUID, {
      title: "New Duel Challenge",
      body: "You received a duel challenge. Open Play to respond.",
      prefKey: "notificationDuels",
      data: {
        pb_route: ROUTE_PLAY_DUEL,
        pb_type: TYPE_DUEL,
        challengeId: ref.id,
      },
      category: "pb.duel",
    });

    res.status(200).json({ok: true, status: "invited", challengeId: ref.id});
  } catch (error) {
    logger.error("duelInvite failed", error);
    res.status(400).json({error: String(error.message || error)});
  }
});

exports.duelRespond = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({error: "Method not allowed"});
    return;
  }

  try {
    const uid = await requireUID(req);
    const challengeId = String(req.body?.challengeId || "").trim();
    const accept = !!req.body?.accept;
    if (!challengeId) throw new Error("Missing challengeId");

    await settleExpiredForUser(uid);
    await settleAcceptanceTimeout(challengeId);

    const output = await db.runTransaction(async (txn) => {
      const ref = db.collection("duelChallenges").doc(challengeId);
      const snap = await txn.get(ref);
      if (!snap.exists) throw new Error("Challenge not found");
      const data = snap.data() || {};
      if (String(data.status || "") !== "invited") throw new Error("Challenge not pending");
      const participants = Array.isArray(data.participants) ? data.participants : [];
      if (!participants.includes(uid)) throw new Error("Not a participant");
      const createdByUid = String(data.createdByUid || "");
      const queueType = String(data.queueType || "open");

      if (!accept) {
        if (queueType === "open" && uid !== createdByUid) {
          const responderSnap = await txn.get(db.collection("users").doc(uid));
          const responderRating = clampInt(responderSnap.data()?.duelRating, 0, 1000000, 0);
          const responderDisplayName = String(responderSnap.data()?.displayName || "").trim() || "Player";
          const responderRequirement = duelRequirementForRating(responderRating);
          const creatorOctaves = parseOctaves(data.octaveCount);
          const responderOctaves = parseOctaves(data.opponentRequestedOctaves || creatorOctaves);
          const creatorMinTempo = clampInt(data.requiredMinTempoBPM, 0, 240, 0);
          const creatorLeague = String(data.requiredLeague || duelLeagueForRating(0));
          txn.update(ref, {
            status: "open",
            opponentUid: null,
            opponentDisplayName: null,
            createdByDisplayName: String(data.createdByDisplayName || "").trim() || "Player",
            participants: [createdByUid],
            creatorAccepted: true,
            opponentAccepted: false,
            opponentRequestedOctaves: null,
            scaleName: null,
            objective: duelObjective("Queued", creatorOctaves, creatorMinTempo),
            startedAt: null,
            submissionDeadlineAt: null,
            creatorScore: null,
            opponentScore: null,
            winnerUid: null,
            creatorRatingDelta: 0,
            opponentRatingDelta: 0,
            requiredLeague: creatorLeague,
            requiredMinTempoBPM: creatorMinTempo,
            acceptByAt: null,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          const responderMinTempo = responderRequirement.minTempoBPM;
          const newOpenRef = db.collection("duelChallenges").doc();
          txn.set(newOpenRef, {
            createdByUid: uid,
            createdByDisplayName: responderDisplayName,
            opponentUid: null,
            opponentDisplayName: null,
            participants: [uid],
            status: "open",
            queueType: "open",
            objective: duelObjective("Queued", responderOctaves, responderMinTempo),
            scaleName: null,
            octaveCount: responderOctaves,
            requiredLeague: responderRequirement.league,
            requiredMinTempoBPM: responderMinTempo,
            creatorAccepted: true,
            opponentAccepted: false,
            opponentRequestedOctaves: null,
            creatorScore: null,
            opponentScore: null,
            winnerUid: null,
            creatorRatingDelta: 0,
            opponentRatingDelta: 0,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            startedAt: null,
            submissionDeadlineAt: null,
            completedAt: null,
          });
          return {status: "requeued_both", creatorUid: createdByUid};
        }

        txn.update(ref, {
          status: "canceled",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        const notifyUid = participants.find((p) => p !== uid) || null;
        return {status: "declined", notifyUid};
      }

      let creatorAccepted = data.creatorAccepted !== false;
      let opponentAccepted = !!data.opponentAccepted;
      if (uid === createdByUid) {
        creatorAccepted = true;
      } else {
        opponentAccepted = true;
      }

      const patch = {
        creatorAccepted,
        opponentAccepted,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      txn.update(ref, patch);

      if (creatorAccepted && opponentAccepted) {
        const octaves = parseOctaves(data.octaveCount);
        const requiredMinTempoBPM = clampInt(data.requiredMinTempoBPM, 0, 240, 0);
        const scaleName = randomDuelScaleName();
        txn.update(ref, {
          status: "active",
          startedAt: admin.firestore.FieldValue.serverTimestamp(),
          submissionDeadlineAt: admin.firestore.Timestamp.fromMillis(
              Date.now() + (SUBMISSION_WINDOW_SECONDS * 1000)
          ),
          acceptByAt: null,
          scaleName,
          objective: duelObjective(scaleName, octaves, requiredMinTempoBPM),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return {status: "activated", scaleName, octaves, requiredMinTempoBPM, notifyUids: participants};
      }

      const notifyUid = participants.find((p) => p !== uid) || null;
      return {status: "accepted_waiting_other", notifyUid};
    });

    if (output.status === "activated") {
      const notifyUids = Array.isArray(output.notifyUids) ? output.notifyUids : [];
      await Promise.all(notifyUids.map((participantUid) => safePushToUser(participantUid, {
        title: "Duel Accepted",
        body: "Your duel is active. Record your take when ready.",
        prefKey: "notificationDuels",
        data: {
          pb_route: ROUTE_PLAY_DUEL,
          pb_type: TYPE_DUEL,
          challengeId,
        },
        category: "pb.duel",
      })));
    } else if (output.status === "accepted_waiting_other" && output.notifyUid) {
      await safePushToUser(output.notifyUid, {
        title: "Duel Response Needed",
        body: "Your opponent accepted. Open Play to confirm the duel.",
        prefKey: "notificationDuels",
        data: {
          pb_route: ROUTE_PLAY_DUEL,
          pb_type: TYPE_DUEL,
          challengeId,
        },
        category: "pb.duel",
      });
    } else if (output.status === "declined" && output.notifyUid) {
      await safePushToUser(output.notifyUid, {
        title: "Duel Declined",
        body: "Your duel challenge was declined.",
        prefKey: "notificationDuels",
        data: {
          pb_route: ROUTE_PLAY_DUEL,
          pb_type: TYPE_DUEL,
          challengeId,
        },
        category: "pb.duel",
      });
    } else if (output.status === "requeued_both" && output.creatorUid) {
      await safePushToUser(output.creatorUid, {
        title: "Queue Continuing",
        body: "Opponent declined. You're back in queue.",
        prefKey: "notificationDuels",
        data: {
          pb_route: ROUTE_PLAY_DUEL,
          pb_type: TYPE_DUEL,
          challengeId,
        },
        category: "pb.duel",
      });
    }

    res.status(200).json({ok: true, ...output});
  } catch (error) {
    logger.error("duelRespond failed", error);
    res.status(400).json({error: String(error.message || error)});
  }
});

exports.duelSubmitAttempt = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({error: "Method not allowed"});
    return;
  }

  try {
    const uid = await requireUID(req);
    const challengeId = String(req.body?.challengeId || "").trim();
    const metrics = req.body?.metrics || {};
    if (!challengeId) throw new Error("Missing challengeId");

    await settleExpiredForUser(uid);

    const intonationScore = clampInt(metrics.intonationScore, 0, 100, 0);
    const rhythmScore = clampInt(metrics.rhythmScore, 0, 100, 0);
    const consistencyScore = clampInt(metrics.consistencyScore, 0, 100, 0);
    const noteCount = clampInt(metrics.noteCount, 0, 2000, 0);
    const beatsAnalyzed = clampInt(metrics.beatsAnalyzed, 0, 2000, 0);
    const tempoBPM = clampInt(metrics.tempoBPM, 0, 240, 0);
    if (noteCount <= 0 || beatsAnalyzed <= 0) {
      throw new Error("Metrics are incomplete");
    }
    const derivedScore = computeDerivedScore(intonationScore, rhythmScore, consistencyScore);

    const challengeRef = db.collection("duelChallenges").doc(challengeId);
    const myAttemptRef = challengeRef.collection("attempts").doc(uid);

    const output = await db.runTransaction(async (txn) => {
      const challengeSnap = await txn.get(challengeRef);
      if (!challengeSnap.exists) throw new Error("Challenge not found");
      const challenge = challengeSnap.data() || {};
      if (String(challenge.status || "") !== "active") throw new Error("Challenge is not active");
      const deadlineMs = challenge.submissionDeadlineAt?.toDate ?
        challenge.submissionDeadlineAt.toDate().getTime() : null;
      if (deadlineMs != null && Date.now() > deadlineMs + (SUBMISSION_SETTLE_GRACE_SECONDS * 1000)) {
        throw new Error("Submission window is closed for this duel.");
      }
      const participants = Array.isArray(challenge.participants) ? challenge.participants : [];
      const createdByUid = String(challenge.createdByUid || "");
      if (participants.length !== 2 || !participants.includes(uid)) {
        throw new Error("Not a participant");
      }
      const opponentUid = participants.find((p) => p !== uid);
      if (!opponentUid) throw new Error("Missing opponent");

      let creatorScore = challenge.creatorScore == null ? null : clampInt(challenge.creatorScore, 0, 100, 0);
      let opponentScore = challenge.opponentScore == null ? null : clampInt(challenge.opponentScore, 0, 100, 0);
      if (uid === createdByUid) {
        creatorScore = derivedScore;
      } else {
        opponentScore = derivedScore;
      }

      if (creatorScore != null && opponentScore != null) {
        await applyMatchOutcome({
          txn,
          challengeRef,
          challengeData: challenge,
          createdByUid,
          opponentUid,
          creatorScore,
          opponentScore,
          forceDraw: false,
        });
        txn.set(myAttemptRef, {
          uid,
          intonationScore,
          rhythmScore,
          consistencyScore,
          noteCount,
          beatsAnalyzed,
          tempoBPM,
          derivedScore,
          submittedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        return {finalized: true, derivedScore};
      }

      txn.set(myAttemptRef, {
        uid,
        intonationScore,
        rhythmScore,
        consistencyScore,
        noteCount,
        beatsAnalyzed,
        tempoBPM,
        derivedScore,
        submittedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      if (uid === createdByUid) {
        txn.update(challengeRef, {
          creatorScore: derivedScore,
          lastSubmissionAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } else {
        txn.update(challengeRef, {
          opponentScore: derivedScore,
          lastSubmissionAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      return {finalized: false, derivedScore};
    });

    res.status(200).json({ok: true, ...output});
  } catch (error) {
    logger.error("duelSubmitAttempt failed", error);
    res.status(400).json({error: String(error.message || error)});
  }
});

exports.duelSettleSweep = onSchedule(
    {
      schedule: "every 30 minutes",
      timeZone: "UTC",
    },
    async () => {
      await settleExpiredGlobal();
      logger.info("duelSettleSweep completed");
    }
);

exports.onFriendInviteCreated = onDocumentCreated("invites/{inviteId}", async (event) => {
  try {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data() || {};
    if (String(data.status || "").toLowerCase() !== "pending") return;

    const toUid = String(data.toUid || "").trim();
    const fromUid = String(data.fromUid || "").trim();
    const fromDisplayName = String(data.fromDisplayName || "A PracticeBuddy user").trim();
    if (!toUid || !fromUid || toUid === fromUid) return;
    logger.info("friend invite created", {inviteId: event.params?.inviteId || "", fromUid, toUid});

    await safePushToUser(toUid, {
      title: "New Friend Request",
      body: `${fromDisplayName} sent you a friend request.`,
      prefKey: "notificationFriendRequests",
      data: {
        pb_route: ROUTE_SOCIAL_FRIEND_REQUESTS,
        pb_type: TYPE_FRIEND_REQUEST,
        friendUid: fromUid,
      },
      category: "pb.friend_request",
    });
  } catch (error) {
    logger.error("onFriendInviteCreated failed", error);
  }
});

exports.onFriendChatMessageCreated = onDocumentCreated(
    "friendChats/{threadId}/messages/{messageId}",
    async (event) => {
      try {
        const messageSnap = event.data;
        if (!messageSnap) return;
        const message = messageSnap.data() || {};

        const threadId = String(event.params?.threadId || "").trim();
        const senderUid = String(message.senderUid || "").trim();
        if (!threadId || !senderUid) return;

        const threadSnap = await db.collection("friendChats").doc(threadId).get();
        if (!threadSnap.exists) return;
        const participants = Array.isArray(threadSnap.data()?.participants) ?
          threadSnap.data().participants : [];
        const recipientUid = participants.find((uid) => String(uid || "") !== senderUid);
        if (!recipientUid) return;
        logger.info("friend chat message created", {
          threadId,
          messageId: event.params?.messageId || "",
          senderUid,
          recipientUid: String(recipientUid),
        });

        await safePushToUser(String(recipientUid), {
          title: "New Message",
          body: "You received a new message.",
          prefKey: "notificationMessages",
          data: {
            pb_route: ROUTE_SOCIAL_CHAT,
            pb_type: TYPE_CHAT_MESSAGE,
            threadId: `friend:${threadId}`,
            friendUid: senderUid,
          },
          category: "pb.message",
        });
      } catch (error) {
        logger.error("onFriendChatMessageCreated failed", error);
      }
    }
);

exports.onStudioChatMessageCreated = onDocumentCreated(
    "studios/{studioId}/messages/{messageId}",
    async (event) => {
      try {
        const messageSnap = event.data;
        if (!messageSnap) return;
        const message = messageSnap.data() || {};

        const studioId = String(event.params?.studioId || "").trim();
        const senderUid = String(message.senderUid || "").trim();
        if (!studioId || !senderUid) return;

        const senderName = String(message.senderName || "Studio member").trim();
        const membersSnap = await db.collection("studios")
            .doc(studioId)
            .collection("members")
            .get();
        const recipients = membersSnap.docs
            .map((doc) => String(doc.id || "").trim())
            .filter((uid) => uid && uid !== senderUid);
        if (recipients.length === 0) return;

        logger.info("studio chat message created", {
          studioId,
          messageId: event.params?.messageId || "",
          senderUid,
          recipientCount: recipients.length,
        });

        await Promise.all(recipients.map((recipientUid) => safePushToUser(recipientUid, {
          title: `${senderName}`,
          body: "New studio chat message.",
          prefKey: "notificationMessages",
          data: {
            pb_route: ROUTE_SOCIAL_CHAT,
            pb_type: TYPE_CHAT_MESSAGE,
            threadId: `studio:${studioId}`,
            studioId,
            friendUid: senderUid,
          },
          category: "pb.message",
        })));
      } catch (error) {
        logger.error("onStudioChatMessageCreated failed", error);
      }
    }
);

async function settleExpiredGlobal() {
  const nowMs = Date.now();
  const expired = await db.collection("duelChallenges")
      .where("status", "==", "active")
      .limit(500)
      .get();

  for (const doc of expired.docs) {
    const data = doc.data() || {};
    const deadline = data.submissionDeadlineAt?.toDate ? data.submissionDeadlineAt.toDate().getTime() : null;
    if (deadline != null && (deadline + (SUBMISSION_SETTLE_GRACE_SECONDS * 1000)) <= nowMs) {
      await settleChallengeById(doc.id);
    }
  }
}

async function settleExpiredForUser(uid) {
  const nowMs = Date.now();
  const expired = await db.collection("duelChallenges")
      .where("participants", "array-contains", uid)
      .limit(25)
      .get();
  for (const doc of expired.docs) {
    const data = doc.data() || {};
    if (String(data.status || "") !== "active") continue;
    const deadline = data.submissionDeadlineAt?.toDate ? data.submissionDeadlineAt.toDate().getTime() : null;
    if (deadline != null && (deadline + (SUBMISSION_SETTLE_GRACE_SECONDS * 1000)) <= nowMs) {
      await settleChallengeById(doc.id);
    }
  }
}

async function settleAcceptanceTimeout(challengeId) {
  const ref = db.collection("duelChallenges").doc(challengeId);
  await db.runTransaction(async (txn) => {
    const snap = await txn.get(ref);
    if (!snap.exists) return;
    const data = snap.data() || {};
    if (String(data.status || "") !== "invited") return;
    const acceptByAt = data.acceptByAt?.toDate ? data.acceptByAt.toDate() : null;
    if (!acceptByAt || acceptByAt.getTime() > Date.now()) return;

    const createdByUid = String(data.createdByUid || "");
    const queueType = String(data.queueType || "open");
    if (queueType === "open" && createdByUid) {
      const octaves = parseOctaves(data.octaveCount);
      const minTempo = clampInt(data.requiredMinTempoBPM, 0, 240, 0);
      txn.update(ref, {
        status: "open",
        opponentUid: null,
        participants: [createdByUid],
        creatorAccepted: true,
        opponentAccepted: false,
        opponentRequestedOctaves: null,
        objective: duelObjective("Queued", octaves, minTempo),
        scaleName: null,
        requiredLeague: String(data.requiredLeague || duelLeagueForRating(0)),
        requiredMinTempoBPM: minTempo,
        startedAt: null,
        submissionDeadlineAt: null,
        creatorScore: null,
        opponentScore: null,
        winnerUid: null,
        creatorRatingDelta: 0,
        opponentRatingDelta: 0,
        acceptByAt: null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else {
      txn.update(ref, {
        status: "canceled",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  });
}

async function settleChallengeById(challengeId) {
  const challengeRef = db.collection("duelChallenges").doc(challengeId);
  await db.runTransaction(async (txn) => {
    const snap = await txn.get(challengeRef);
    if (!snap.exists) return;
    const data = snap.data() || {};
    if (String(data.status || "") !== "active") return;
    const deadline = data.submissionDeadlineAt?.toDate ? data.submissionDeadlineAt.toDate() : null;
    if (!deadline || (deadline.getTime() + (SUBMISSION_SETTLE_GRACE_SECONDS * 1000)) > Date.now()) return;

    const createdByUid = String(data.createdByUid || "");
    const participants = Array.isArray(data.participants) ? data.participants : [];
    if (!createdByUid || participants.length !== 2) return;
    const opponentUid = participants.find((p) => p !== createdByUid);
    if (!opponentUid) return;

    const creatorScore = data.creatorScore == null ? null : clampInt(data.creatorScore, 0, 100, 0);
    const opponentScore = data.opponentScore == null ? null : clampInt(data.opponentScore, 0, 100, 0);

    if (creatorScore == null && opponentScore == null) {
      await applyMatchOutcome({
        txn,
        challengeRef,
        challengeData: data,
        createdByUid,
        opponentUid,
        creatorScore: 0,
        opponentScore: 0,
        forceDraw: true,
      });
      return;
    }

    if (creatorScore != null && opponentScore == null) {
      await applyMatchOutcome({
        txn,
        challengeRef,
        challengeData: data,
        createdByUid,
        opponentUid,
        creatorScore,
        opponentScore: -1,
        forceDraw: true,
      });
      return;
    }

    if (creatorScore == null && opponentScore != null) {
      await applyMatchOutcome({
        txn,
        challengeRef,
        challengeData: data,
        createdByUid,
        opponentUid,
        creatorScore: -1,
        opponentScore,
        forceDraw: true,
      });
      return;
    }

    await applyMatchOutcome({
      txn,
      challengeRef,
      challengeData: data,
      createdByUid,
      opponentUid,
      creatorScore,
      opponentScore,
      forceDraw: false,
    });
  });
}

async function applyMatchOutcome({
  txn,
  challengeRef,
  challengeData,
  createdByUid,
  opponentUid,
  creatorScore,
  opponentScore,
  forceDraw,
}) {
  const octaves = parseOctaves(challengeData.octaveCount);
  const rewards = rewardForOctaves(octaves);
  const seasonKey = currentSeasonKey();

  let creatorOutcome = 0.5;
  let opponentOutcome = 0.5;
  let winnerUid = null;
  let creatorDelta = 0;
  let opponentDelta = 0;
  let creatorTokenDelta = 0;
  let opponentTokenDelta = 0;

  if (!forceDraw && creatorScore !== opponentScore) {
    if (creatorScore > opponentScore) {
      creatorOutcome = 1;
      opponentOutcome = 0;
      winnerUid = createdByUid;
      creatorDelta = rewards.rating;
      opponentDelta = -rewards.rating;
      creatorTokenDelta = rewards.tokens;
    } else {
      creatorOutcome = 0;
      opponentOutcome = 1;
      winnerUid = opponentUid;
      creatorDelta = -rewards.rating;
      opponentDelta = rewards.rating;
      opponentTokenDelta = rewards.tokens;
    }
  }

  const creatorRef = db.collection("users").doc(createdByUid);
  const opponentRef = db.collection("users").doc(opponentUid);
  const creatorSnap = await txn.get(creatorRef);
  const opponentSnap = await txn.get(opponentRef);

  const creatorCurrent = creatorSnap.data() || {};
  const opponentCurrent = opponentSnap.data() || {};
  const creatorRating = clampInt(creatorCurrent.duelRating, 0, 1000000, 0);
  const opponentRating = clampInt(opponentCurrent.duelRating, 0, 1000000, 0);

  applyUserResult(txn, creatorRef, creatorCurrent, {
    outcome: creatorOutcome,
    newRating: Math.max(0, creatorRating + creatorDelta),
    ratingDelta: creatorDelta,
    tokenDelta: creatorTokenDelta,
    seasonKey,
  });
  applyUserResult(txn, opponentRef, opponentCurrent, {
    outcome: opponentOutcome,
    newRating: Math.max(0, opponentRating + opponentDelta),
    ratingDelta: opponentDelta,
    tokenDelta: opponentTokenDelta,
    seasonKey,
  });

  txn.update(challengeRef, {
    status: "completed",
    winnerUid: winnerUid,
    creatorScore: creatorScore < 0 ? null : creatorScore,
    opponentScore: opponentScore < 0 ? null : opponentScore,
    creatorRatingDelta: creatorDelta,
    opponentRatingDelta: opponentDelta,
    lastSubmissionAt: admin.firestore.FieldValue.serverTimestamp(),
    completedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

function applyUserResult(txn, userRef, current, {outcome, newRating, ratingDelta, tokenDelta, seasonKey}) {
  const wins = clampInt(current.duelWins, 0, 1000000, 0) + (outcome === 1 ? 1 : 0);
  const losses = clampInt(current.duelLosses, 0, 1000000, 0) + (outcome === 0 ? 1 : 0);
  const draws = clampInt(current.duelDraws, 0, 1000000, 0) + (outcome === 0.5 ? 1 : 0);

  const currentSeason = String(current.duelSeasonKey || "");
  const reset = currentSeason !== seasonKey;
  const oldSeasonPoints = reset ? 0 : clampInt(current.duelSeasonPoints, 0, 1000000, 0);
  const oldSeasonMatches = reset ? 0 : clampInt(current.duelSeasonMatches, 0, 1000000, 0);
  const oldSeasonWins = reset ? 0 : clampInt(current.duelSeasonWins, 0, 1000000, 0);
  const oldSeasonRatingDelta = reset ? 0 : clampInt(current.duelSeasonRatingDelta, -1000000, 1000000, 0);
  const oldTokens = clampInt(current.duelTokens, 0, 1000000, 0);

  txn.set(userRef, {
    duelRating: Math.max(0, newRating),
    duelLeague: duelLeagueForRating(newRating),
    duelWins: wins,
    duelLosses: losses,
    duelDraws: draws,
    duelSeasonKey: seasonKey,
    duelSeasonPoints: oldSeasonPoints + (outcome === 1 ? 3 : (outcome === 0.5 ? 1 : 0)),
    duelSeasonMatches: oldSeasonMatches + 1,
    duelSeasonWins: oldSeasonWins + (outcome === 1 ? 1 : 0),
    duelSeasonRatingDelta: oldSeasonRatingDelta + ratingDelta,
    duelTokens: oldTokens + Math.max(0, tokenDelta),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}

function rewardForOctaves(octaves) {
  if (octaves === 3) return {rating: 22, tokens: 16};
  if (octaves === 2) return {rating: 18, tokens: 12};
  return {rating: 14, tokens: 8};
}

function randomDuelScaleName() {
  const major = ["C", "G", "D", "A", "E", "B", "F#", "Db", "Ab", "Eb", "Bb", "F"]
      .map((r) => `${r} major`);
  const melodicMinor = ["A", "E", "B", "F#", "C#", "G#", "D#", "Bb", "F", "C", "G", "D"]
      .map((r) => `${r} melodic minor`);
  const pool = major.concat(melodicMinor);
  return pool[Math.floor(Math.random() * pool.length)] || "C major";
}

async function requireUID(req) {
  const authHeader = req.get("Authorization") || "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.substring(7) : "";
  if (!token) throw new Error("Missing auth token");
  const decoded = await admin.auth().verifyIdToken(token);
  const uid = String(decoded.uid || "").trim();
  if (!uid) throw new Error("Invalid auth user");
  return uid;
}

function parseInviteSource(value) {
  const raw = String(value || "").toLowerCase();
  if (raw === "studio") return "studio";
  return "friend";
}

function parseOctaves(value) {
  const n = clampInt(value, 1, 3, 1);
  if (n === 2) return 2;
  if (n === 3) return 3;
  return 1;
}

function duelLeagueForRating(rating) {
  if (rating >= 2000) return "grandmaster";
  if (rating >= 1600) return "master";
  if (rating >= 1250) return "diamond";
  if (rating >= 950) return "emerald";
  if (rating >= 700) return "platinum";
  if (rating >= 450) return "gold";
  if (rating >= 200) return "silver";
  return "bronze";
}

function duelRequirementForRating(rating) {
  const league = duelLeagueForRating(clampInt(rating, 0, 1000000, 0));
  switch (league) {
    case "grandmaster":
      return {league, octaves: 3, minTempoBPM: 136};
    case "master":
      return {league, octaves: 3, minTempoBPM: 126};
    case "diamond":
      return {league, octaves: 3, minTempoBPM: 116};
    case "emerald":
      return {league, octaves: 3, minTempoBPM: 104};
    case "platinum":
      return {league, octaves: 3, minTempoBPM: 88};
    case "gold":
      return {league, octaves: 3, minTempoBPM: 0};
    case "silver":
      return {league, octaves: 2, minTempoBPM: 0};
    default:
      return {league: "bronze", octaves: 1, minTempoBPM: 0};
  }
}

function maxDuelRequirement(left, right) {
  const first = left || {league: "bronze", octaves: 1, minTempoBPM: 0};
  const second = right || {league: "bronze", octaves: 1, minTempoBPM: 0};
  return {
    league: leagueRank(first.league) >= leagueRank(second.league) ? first.league : second.league,
    octaves: Math.max(parseOctaves(first.octaves), parseOctaves(second.octaves)),
    minTempoBPM: Math.max(clampInt(first.minTempoBPM, 0, 240, 0), clampInt(second.minTempoBPM, 0, 240, 0)),
  };
}

function leagueRank(league) {
  const order = [
    "bronze",
    "silver",
    "gold",
    "platinum",
    "emerald",
    "diamond",
    "master",
    "grandmaster",
  ];
  const i = order.indexOf(String(league || "").toLowerCase());
  return i >= 0 ? i : 0;
}

function duelObjective(prefix, octaves, minTempoBPM) {
  const base = `${prefix} • ${octaves} octave${octaves === 1 ? "" : "s"}`;
  if (minTempoBPM > 0) {
    return `${base} • ${minTempoBPM}+ BPM`;
  }
  return base;
}

function duelQualityThresholdForLeague(league) {
  switch (String(league || "").toLowerCase()) {
    case "grandmaster":
      return {minNotes: 220, minBeats: 44};
    case "master":
      return {minNotes: 200, minBeats: 42};
    case "diamond":
      return {minNotes: 180, minBeats: 40};
    case "emerald":
      return {minNotes: 160, minBeats: 36};
    case "platinum":
      return {minNotes: 145, minBeats: 34};
    case "gold":
      return {minNotes: 130, minBeats: 32};
    case "silver":
      return {minNotes: 95, minBeats: 24};
    default:
      return {minNotes: 70, minBeats: 16};
  }
}

function computeDerivedScore(intonationScore, rhythmScore, consistencyScore) {
  const weighted = (intonationScore * 0.5) + (rhythmScore * 0.35) + (consistencyScore * 0.15);
  return clampInt(Math.round(weighted), 0, 100, 0);
}

function currentSeasonKey() {
  const now = new Date();
  const utc = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  const day = utc.getUTCDay() || 7;
  utc.setUTCDate(utc.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(utc.getUTCFullYear(), 0, 1));
  const week = Math.ceil((((utc - yearStart) / 86400000) + 1) / 7);
  return `${utc.getUTCFullYear()}-W${week}`;
}

function clampInt(value, min, max, fallback = min) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, Math.round(n)));
}

async function safePushToUser(uid, {title, body, prefKey, data, category}) {
  try {
    await pushToUser(uid, {title, body, prefKey, data, category});
  } catch (error) {
    logger.warn("push notification failed", {uid, error: String(error?.message || error)});
  }
}

async function pushToUser(uid, {title, body, prefKey, data, category}) {
  const normalizedUid = String(uid || "").trim();
  if (!normalizedUid) return;

  const userSnap = await db.collection("users").doc(normalizedUid).get();
  if (!userSnap.exists) return;
  const userData = userSnap.data() || {};
  if (prefKey && userData[prefKey] === false) return;

  const deviceSnap = await db.collection("users")
      .doc(normalizedUid)
      .collection("devices")
      .get();
  const tokenRows = deviceSnap.docs
      .map((doc) => ({
        token: String(doc.data()?.token || "").trim(),
        tokenType: String(doc.data()?.tokenType || "legacy").trim().toLowerCase(),
      }))
      .filter((row) => row.token.length > 0);
  const tokens = tokenRows
      .filter((row) => {
        if (row.tokenType === "apns") return false;
        if (row.tokenType === "fcm") return true;
        return !isLikelyAPNSToken(row.token);
      })
      .map((row) => row.token);
  if (tokens.length === 0) {
    if (tokenRows.length > 0) {
      logger.warn("No FCM-compatible push token available for user", {uid: normalizedUid});
    }
    return;
  }

  const payloadData = normalizePushData(data);
  logger.info("sending push notification", {
    uid: normalizedUid,
    tokenCount: tokens.length,
    prefKey: prefKey || "",
    category: category || "",
  });
  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {
      title: String(title || "PracticeBuddy"),
      body: String(body || ""),
    },
    data: payloadData,
    apns: {
      payload: {
        aps: {
          sound: "default",
          category: String(category || ""),
        },
      },
    },
  });
  logger.info("push send result", {
    uid: normalizedUid,
    successCount: response.successCount,
    failureCount: response.failureCount,
  });
  await pruneInvalidDeviceTokens(normalizedUid, tokens, response.responses);
}

function normalizePushData(data) {
  const output = {};
  Object.entries(data || {}).forEach(([key, value]) => {
    if (value == null) return;
    output[String(key)] = String(value);
  });
  return output;
}

function sanitizeActiveProductIDs(value) {
  if (!Array.isArray(value)) return [];
  const normalized = value
      .map((item) => String(item || "").trim())
      .filter((id) => id.length > 0 && PRO_SUBSCRIPTION_PRODUCT_IDS.has(id));
  return Array.from(new Set(normalized)).sort();
}

function isLikelyAPNSToken(token) {
  const trimmed = String(token || "").trim();
  if (trimmed.length < 64 || trimmed.length > 256) return false;
  return /^[a-fA-F0-9]+$/.test(trimmed);
}

async function pruneInvalidDeviceTokens(uid, tokens, responses) {
  if (!Array.isArray(tokens) || !Array.isArray(responses)) return;
  const staleTokens = [];
  responses.forEach((result, index) => {
    if (!result || !result.error) return;
    const code = String(result.error.code || "");
    if (code.includes("registration-token-not-registered") || code.includes("invalid-registration-token")) {
      staleTokens.push(tokens[index]);
    }
  });
  if (staleTokens.length === 0) return;
  logger.warn("pruning stale push tokens", {uid, staleCount: staleTokens.length});

  for (const token of staleTokens) {
    const docs = await db.collection("users")
        .doc(uid)
        .collection("devices")
        .where("token", "==", token)
        .limit(5)
        .get();
    await Promise.all(docs.docs.map((doc) => doc.ref.delete()));
  }
}
