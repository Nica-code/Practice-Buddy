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
const MAX_PENDING_INVITES_PER_USER = 5;

const ROUTE_PLAY_DUEL = "play_duel";
const ROUTE_SOCIAL_FRIEND_REQUESTS = "social_friend_requests";
const ROUTE_SOCIAL_CHAT = "social_chat";
const TYPE_DUEL = "duel";
const TYPE_FRIEND_REQUEST = "friend_request";
const TYPE_CHAT_MESSAGE = "chat_message";

exports.duelQueueJoin = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({error: "Method not allowed"});
    return;
  }

  try {
    const uid = await requireUID(req);
    const octaves = parseOctaves(req.body?.octaves);

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

        txn.update(ref, {
          status: "invited",
          queueType: "open",
          opponentUid: uid,
          participants: [creatorUID, uid],
          creatorAccepted: true,
          opponentAccepted: false,
          opponentRequestedOctaves: octaves,
          octaveCount: creatorOctaves,
          objective: "Match found • awaiting acceptance",
          matchFoundAt: admin.firestore.FieldValue.serverTimestamp(),
          acceptByAt: admin.firestore.Timestamp.fromMillis(now + (ACCEPT_WINDOW_SECONDS * 1000)),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return {
          status: "matched_pending_accept",
          challengeId: ref.id,
          octaves: creatorOctaves,
          notifyUid: creatorUID,
        };
      }

      const ref = db.collection("duelChallenges").doc();
      txn.set(ref, {
        createdByUid: uid,
        opponentUid: null,
        participants: [uid],
        status: "open",
        queueType: "open",
        objective: `Queued • ${octaves} octave${octaves === 1 ? "" : "s"}`,
        scaleName: null,
        octaveCount: octaves,
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
      return {status: "queued", challengeId: ref.id, octaves};
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
    const octaves = parseOctaves(req.body?.octaves);
    if (!targetUID || targetUID === uid) {
      throw new Error("Invalid target");
    }

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
      opponentUid: targetUID,
      participants: [uid, targetUID],
      status: "invited",
      queueType: source,
      objective: `Challenge • ${octaves} octave${octaves === 1 ? "" : "s"}`,
      scaleName: null,
      octaveCount: octaves,
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
          const creatorOctaves = parseOctaves(data.octaveCount);
          const responderOctaves = parseOctaves(data.opponentRequestedOctaves || creatorOctaves);
          txn.update(ref, {
            status: "open",
            opponentUid: null,
            participants: [createdByUid],
            creatorAccepted: true,
            opponentAccepted: false,
            opponentRequestedOctaves: null,
            scaleName: null,
            objective: `Queued • ${creatorOctaves} octave${creatorOctaves === 1 ? "" : "s"}`,
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

          const newOpenRef = db.collection("duelChallenges").doc();
          txn.set(newOpenRef, {
            createdByUid: uid,
            opponentUid: null,
            participants: [uid],
            status: "open",
            queueType: "open",
            objective: `Queued • ${responderOctaves} octave${responderOctaves === 1 ? "" : "s"}`,
            scaleName: null,
            octaveCount: responderOctaves,
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
        const scaleName = randomDuelScaleName();
        txn.update(ref, {
          status: "active",
          startedAt: admin.firestore.FieldValue.serverTimestamp(),
          submissionDeadlineAt: admin.firestore.Timestamp.fromMillis(
              Date.now() + (SUBMISSION_WINDOW_SECONDS * 1000)
          ),
          acceptByAt: null,
          scaleName,
          objective: `${scaleName} • ${octaves} octave${octaves === 1 ? "" : "s"}`,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return {status: "activated", scaleName, octaves, notifyUids: participants};
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

      const participants = Array.isArray(challenge.participants) ? challenge.participants : [];
      const createdByUid = String(challenge.createdByUid || "");
      if (participants.length !== 2 || !participants.includes(uid)) {
        throw new Error("Not a participant");
      }
      const opponentUid = participants.find((p) => p !== uid);
      if (!opponentUid) throw new Error("Missing opponent");

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

      let creatorScore = challenge.creatorScore == null ? null : clampInt(challenge.creatorScore, 0, 100, 0);
      let opponentScore = challenge.opponentScore == null ? null : clampInt(challenge.opponentScore, 0, 100, 0);
      if (uid === createdByUid) {
        creatorScore = derivedScore;
        txn.update(challengeRef, {creatorScore: derivedScore, updatedAt: admin.firestore.FieldValue.serverTimestamp()});
      } else {
        opponentScore = derivedScore;
        txn.update(challengeRef, {opponentScore: derivedScore, updatedAt: admin.firestore.FieldValue.serverTimestamp()});
      }

      if (creatorScore == null || opponentScore == null) {
        return {finalized: false, derivedScore};
      }

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
      return {finalized: true, derivedScore};
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

        const senderName = String(message.senderName || "New message").trim() || "New message";
        const text = String(message.text || "").trim();
        const body = text.length > 120 ? `${text.slice(0, 117)}...` : text;
        await safePushToUser(String(recipientUid), {
          title: senderName,
          body: body || "You received a new message.",
          prefKey: "notificationMessages",
          data: {
            pb_route: ROUTE_SOCIAL_CHAT,
            pb_type: TYPE_CHAT_MESSAGE,
            threadId,
            friendUid: senderUid,
          },
          category: "pb.message",
        });
      } catch (error) {
        logger.error("onFriendChatMessageCreated failed", error);
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
    if (deadline != null && deadline <= nowMs) {
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
    if (deadline != null && deadline <= nowMs) {
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
      txn.update(ref, {
        status: "open",
        opponentUid: null,
        participants: [createdByUid],
        creatorAccepted: true,
        opponentAccepted: false,
        opponentRequestedOctaves: null,
        objective: `Queued • ${octaves} octave${octaves === 1 ? "" : "s"}`,
        scaleName: null,
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
    if (!deadline || deadline.getTime() > Date.now()) return;

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
  if (rating >= 450) return "gold";
  if (rating >= 200) return "silver";
  return "bronze";
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
  const tokens = deviceSnap.docs
      .map((doc) => String(doc.data()?.token || "").trim())
      .filter((token) => token.length > 0);
  if (tokens.length === 0) return;

  const payloadData = normalizePushData(data);
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
