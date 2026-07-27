const functions = require("firebase-functions");
const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/https");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onDocumentCreated, onDocumentWritten} = require("firebase-functions/v2/firestore");
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
  "com.alexmalaimare.practiquest.pro.monthly",
  "com.alexmalaimare.practicebuddy.adfree.monthly",
]);

const ROUTE_PLAY_DUEL = "play_duel";
const ROUTE_SOCIAL_FRIEND_REQUESTS = "social_friend_requests";
const ROUTE_SOCIAL_CHAT = "social_chat";
const TYPE_DUEL = "duel";
const TYPE_FRIEND_REQUEST = "friend_request";
const TYPE_CHAT_MESSAGE = "chat_message";
const PROFILE_SCHEMA_VERSION = 2;
const HANDLE_COOLDOWN_MS = 30 * 24 * 60 * 60 * 1000;
const HANDLE_REDIRECT_MS = 90 * 24 * 60 * 60 * 1000;
const MOMENT_LIFETIME_MS = 24 * 60 * 60 * 1000;
const MAX_MOMENT_FANOUT = 500;
const VALID_MOMENT_TAGS = new Set([
  "breakthrough", "focusedWork", "firstRun", "toughDay", "consistency", "performancePrep",
]);
const VALID_MOMENT_AUDIENCES = new Set(["friends", "followers"]);
const VALID_MOMENT_REACTIONS = new Set(["bravo", "inspired", "strongWork", "practiceTogether"]);
const INTERNAL_CALLABLE_AUTH = Symbol("internalCallableAuth");

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
    const result = await sendPushTestNotification(uid, req.body || {});
    res.status(200).json({ok: true, ...result});
  } catch (error) {
    logger.error("pushTestNotification failed", error);
    if (error?.reason) {
      res.status(409).json({
        ok: false,
        error: String(error.message || error),
        reason: error.reason,
        detail: error.detail || null,
        failureCodes: error.failureCodes || [],
      });
      return;
    }
    res.status(400).json({error: String(error.message || error)});
  }
});

exports.deleteAccount = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({error: "Method not allowed"});
    return;
  }

  try {
    const uid = await requireUID(req);
    await deleteAccountAndData(uid);
    res.status(200).json({ok: true});
  } catch (error) {
    logger.error("deleteAccount failed", error);
    res.status(400).json({error: String(error.message || error)});
  }
});

// Identity writes are server-authoritative: private account data lives in
// users/{uid}; the intentionally small public projection is the only profile
// document the social surfaces are allowed to query.
exports.identityCompleteProfile = onRequest({maxInstances: 5}, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({error: "Method not allowed"});
    return;
  }
  try {
    const auth = await requireAuth(req);
    if (auth.token.firebase?.sign_in_provider === "anonymous") {
      throw new Error("Create a permanent account before completing a public profile.");
    }
    const input = parseIdentityInput(req.body || {});
    const output = await completeIdentityProfile(auth.uid, input, {allowExisting: true});
    res.status(200).json({ok: true, ...output});
  } catch (error) {
    logger.warn("identityCompleteProfile failed", {error: String(error?.message || error)});
    res.status(400).json({error: String(error?.message || error)});
  }
});

exports.identityChangeHandle = onRequest({maxInstances: 5}, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({error: "Method not allowed"});
    return;
  }
  try {
    const auth = await requireAuth(req);
    if (auth.token.firebase?.sign_in_provider === "anonymous") {
      throw new Error("Create a permanent account before changing a handle.");
    }
    const handle = validateHandle(req.body?.handle);
    const output = await changeHandle(auth.uid, handle);
    res.status(200).json({ok: true, ...output});
  } catch (error) {
    logger.warn("identityChangeHandle failed", {error: String(error?.message || error)});
    res.status(400).json({error: String(error?.message || error)});
  }
});

exports.identityUpdatePrivacy = onRequest({maxInstances: 5}, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({error: "Method not allowed"});
    return;
  }
  try {
    const auth = await requireAuth(req);
    if (auth.token.firebase?.sign_in_provider === "anonymous") {
      throw new Error("Create a permanent profile before changing social privacy.");
    }
    await updateIdentityPrivacy(auth.uid, parseProfilePrivacy(req.body?.privacy));
    res.status(200).json({ok: true});
  } catch (error) {
    logger.warn("identityUpdatePrivacy failed", {error: String(error?.message || error)});
    res.status(400).json({error: String(error?.message || error)});
  }
});

exports.friendInviteByCode = onRequest({maxInstances: 5}, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({error: "Method not allowed"});
    return;
  }
  try {
    const auth = await requireAuth(req);
    if (auth.token.firebase?.sign_in_provider === "anonymous") {
      throw new Error("Create a permanent profile before sending a friend request.");
    }
    const code = String(req.body?.friendCode || "").trim().toUpperCase();
    if (!/^[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(code)) throw new Error("Enter a valid friend code.");
    const output = await createFriendInviteByCode(auth.uid, code);
    res.status(200).json({ok: true, ...output});
  } catch (error) {
    logger.warn("friendInviteByCode failed", {error: String(error?.message || error)});
    res.status(400).json({error: String(error?.message || error)});
  }
});

// Moments contain only a whitelisted generated-card schema. No text supplied
// by the client is persisted other than the fixed category enum below.
exports.practiceMomentCreate = onRequest({maxInstances: 5}, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({error: "Method not allowed"});
    return;
  }
  try {
    const auth = await requireAuth(req);
    if (auth.token.firebase?.sign_in_provider === "anonymous") {
      throw new Error("Create a permanent profile before sharing a Moment.");
    }
    const input = parseMomentInput(req.body || {});
    const result = await createPracticeMoment(auth.uid, input);
    res.status(200).json({ok: true, ...result});
  } catch (error) {
    logger.warn("practiceMomentCreate failed", {error: String(error?.message || error)});
    res.status(400).json({error: String(error?.message || error)});
  }
});

exports.practiceMomentReact = onRequest({maxInstances: 5}, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({error: "Method not allowed"});
    return;
  }
  try {
    const auth = await requireAuth(req);
    const momentID = validateDocumentID(req.body?.momentID, "Moment");
    const reaction = String(req.body?.reaction || "");
    if (!VALID_MOMENT_REACTIONS.has(reaction)) {
      throw new Error("Choose a valid reaction.");
    }
    await reactToPracticeMoment(auth.uid, momentID, reaction);
    res.status(200).json({ok: true});
  } catch (error) {
    logger.warn("practiceMomentReact failed", {error: String(error?.message || error)});
    res.status(400).json({error: String(error?.message || error)});
  }
});

// Social relationships are server-authoritative. Clients never write follows,
// blocks, reports, or request state directly, which keeps private account data
// out of public social collections and lets age/relationship rules stay
// consistent across every UI entry point.
exports.socialAction = onRequest({maxInstances: 5}, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({error: "Method not allowed"});
    return;
  }
  try {
    const auth = await requireAuth(req);
    if (auth.token.firebase?.sign_in_provider === "anonymous") {
      throw new Error("Create a permanent profile before using community actions.");
    }
    const action = String(req.body?.action || "");
    const targetUID = validateDocumentID(req.body?.targetUID, "Musician");
    const result = await applySocialAction(auth.uid, targetUID, action, req.body?.reason);
    res.status(200).json({ok: true, ...result});
  } catch (error) {
    logger.warn("socialAction failed", {error: String(error?.message || error)});
    res.status(400).json({error: String(error?.message || error)});
  }
});

exports.socialConnections = onRequest({maxInstances: 5}, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({error: "Method not allowed"});
    return;
  }
  try {
    const auth = await requireAuth(req);
    if (auth.token.firebase?.sign_in_provider === "anonymous") {
      throw new Error("Create a permanent profile before viewing connections.");
    }
    const section = String(req.body?.section || "following");
    const output = await socialConnectionRows(auth.uid, section);
    res.status(200).json({ok: true, section, rows: output});
  } catch (error) {
    logger.warn("socialConnections failed", {error: String(error?.message || error)});
    res.status(400).json({error: String(error?.message || error)});
  }
});

exports.socialRelationship = onRequest({maxInstances: 5}, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({error: "Method not allowed"});
    return;
  }
  try {
    const auth = await requireAuth(req);
    if (auth.token.firebase?.sign_in_provider === "anonymous") {
      throw new Error("Create a permanent profile before viewing relationships.");
    }
    const targetUID = validateDocumentID(req.body?.targetUID, "Musician");
    const state = await socialRelationshipState(auth.uid, targetUID);
    res.status(200).json({ok: true, state});
  } catch (error) {
    logger.warn("socialRelationship failed", {error: String(error?.message || error)});
    res.status(400).json({error: String(error?.message || error)});
  }
});

// V2 callable endpoints are the App Check-protected client surface. The
// existing HTTP exports remain temporarily for already-shipped clients and
// are removed only after adoption is verified.
exports.socialActionV2 = onCall(
    {enforceAppCheck: true, maxInstances: 5},
    async (request) => {
      try {
        const auth = requireCallablePermanentAuth(request);
        const action = String(request.data?.action || "");
        const targetUID = validateDocumentID(request.data?.targetUID, "Musician");
        const result = await applySocialAction(auth.uid, targetUID, action, request.data?.reason);
        return {ok: true, ...result};
      } catch (error) {
        logger.warn("socialActionV2 failed", {error: String(error?.message || error)});
        throw asCallableError(error);
      }
    },
);

exports.socialConnectionsV2 = onCall(
    {enforceAppCheck: true, maxInstances: 5},
    async (request) => {
      try {
        const auth = requireCallablePermanentAuth(request);
        const section = String(request.data?.section || "following");
        const rows = await socialConnectionRows(auth.uid, section);
        return {ok: true, section, rows};
      } catch (error) {
        logger.warn("socialConnectionsV2 failed", {error: String(error?.message || error)});
        throw asCallableError(error);
      }
    },
);

exports.socialRelationshipV2 = onCall(
    {enforceAppCheck: true, maxInstances: 5},
    async (request) => {
      try {
        const auth = requireCallablePermanentAuth(request);
        const targetUID = validateDocumentID(request.data?.targetUID, "Musician");
        const state = await socialRelationshipState(auth.uid, targetUID);
        return {ok: true, state};
      } catch (error) {
        logger.warn("socialRelationshipV2 failed", {error: String(error?.message || error)});
        throw asCallableError(error);
      }
    },
);

exports.identityCompleteProfileV2 = onCall(
    {enforceAppCheck: true, maxInstances: 5},
    async (request) => {
      try {
        const auth = requireCallablePermanentAuth(request);
        const input = parseIdentityInput(request.data || {});
        const output = await completeIdentityProfile(auth.uid, input, {allowExisting: true});
        return {ok: true, ...output};
      } catch (error) {
        logger.warn("identityCompleteProfileV2 failed", {error: String(error?.message || error)});
        throw asCallableError(error);
      }
    },
);

exports.identityChangeHandleV2 = onCall(
    {enforceAppCheck: true, maxInstances: 5},
    async (request) => {
      try {
        const auth = requireCallablePermanentAuth(request);
        const handle = validateHandle(request.data?.handle);
        const output = await changeHandle(auth.uid, handle);
        return {ok: true, ...output};
      } catch (error) {
        logger.warn("identityChangeHandleV2 failed", {error: String(error?.message || error)});
        throw asCallableError(error);
      }
    },
);

exports.identityUpdatePrivacyV2 = onCall(
    {enforceAppCheck: true, maxInstances: 5},
    async (request) => {
      try {
        const auth = requireCallablePermanentAuth(request);
        await updateIdentityPrivacy(auth.uid, parseProfilePrivacy(request.data?.privacy));
        return {ok: true};
      } catch (error) {
        logger.warn("identityUpdatePrivacyV2 failed", {error: String(error?.message || error)});
        throw asCallableError(error);
      }
    },
);

exports.friendInviteByCodeV2 = onCall(
    {enforceAppCheck: true, maxInstances: 5},
    async (request) => {
      try {
        const auth = requireCallablePermanentAuth(request);
        const code = String(request.data?.friendCode || "").trim().toUpperCase();
        if (!/^[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(code)) {
          throw new Error("Enter a valid friend code.");
        }
        const output = await createFriendInviteByCode(auth.uid, code);
        return {ok: true, ...output};
      } catch (error) {
        logger.warn("friendInviteByCodeV2 failed", {error: String(error?.message || error)});
        throw asCallableError(error);
      }
    },
);

exports.friendActionV2 = onCall(
    {enforceAppCheck: true, maxInstances: 5},
    async (request) => {
      try {
        const auth = requireCallablePermanentAuth(request);
        const action = String(request.data?.action || "");
        const output = await applyFriendAction(auth.uid, action, request.data || {});
        return {ok: true, ...output};
      } catch (error) {
        logger.warn("friendActionV2 failed", {error: String(error?.message || error)});
        throw asCallableError(error);
      }
    },
);

exports.practiceMomentCreateV2 = onCall(
    {enforceAppCheck: true, maxInstances: 5},
    async (request) => {
      try {
        const auth = requireCallablePermanentAuth(request);
        const input = parseMomentInput(request.data || {});
        const result = await createPracticeMoment(auth.uid, input);
        return {ok: true, ...result};
      } catch (error) {
        logger.warn("practiceMomentCreateV2 failed", {error: String(error?.message || error)});
        throw asCallableError(error);
      }
    },
);

exports.practiceMomentReactV2 = onCall(
    {enforceAppCheck: true, maxInstances: 5},
    async (request) => {
      try {
        const auth = requireCallablePermanentAuth(request);
        const momentID = validateDocumentID(request.data?.momentID, "Moment");
        const reaction = String(request.data?.reaction || "");
        if (!VALID_MOMENT_REACTIONS.has(reaction)) {
          throw new Error("Choose a valid reaction.");
        }
        await reactToPracticeMoment(auth.uid, momentID, reaction);
        return {ok: true};
      } catch (error) {
        logger.warn("practiceMomentReactV2 failed", {error: String(error?.message || error)});
        throw asCallableError(error);
      }
    },
);

exports.deleteAccountV2 = onCall(
    {enforceAppCheck: true, maxInstances: 3},
    async (request) => {
      try {
        const auth = requireCallableAuth(request);
        await deleteAccountAndData(auth.uid);
        return {ok: true};
      } catch (error) {
        logger.error("deleteAccountV2 failed", error);
        throw asCallableError(error);
      }
    },
);

exports.pushTestNotificationV2 = onCall(
    {enforceAppCheck: true, maxInstances: 3},
    async (request) => {
      try {
        const auth = requireCallableAuth(request);
        const result = await sendPushTestNotification(auth.uid, request.data || {});
        return {ok: true, ...result};
      } catch (error) {
        logger.error("pushTestNotificationV2 failed", error);
        throw asCallableError(error);
      }
    },
);

// A bounded cleanup is used in addition to read-time expiresAt checks. It
// removes subcollections and inbox references, which Firestore TTL cannot do.
exports.cleanupExpiredPracticeMoments = onSchedule({schedule: "every 60 minutes", timeZone: "UTC", maxInstances: 1}, async () => {
  const now = admin.firestore.Timestamp.now();
  const expired = await db.collection("practiceMoments")
      .where("expiresAt", "<=", now)
      .limit(250)
      .get();
  await Promise.allSettled(expired.docs.map((doc) => deletePracticeMomentEverywhere(doc.id)));
  logger.info("practice Moment cleanup complete", {count: expired.size});
});

// Keep public projections in sync when existing profile/avatar flows update a
// v2 user. The projection function only copies explicit, non-sensitive fields.
exports.syncPublicProfileProjection = onDocumentWritten("users/{uid}", async (event) => {
  const uid = event.params.uid;
  const after = event.data?.after;
  if (!after?.exists) {
    await db.collection("publicProfiles").doc(uid).delete().catch(() => undefined);
    return;
  }
  const user = after.data() || {};
  if (Number(user.profileSchemaVersion || 0) < PROFILE_SCHEMA_VERSION || !String(user.handle || "")) {
    return;
  }
  await db.collection("publicProfiles").doc(uid).set(publicProjectionForUser(user), {merge: true});
});

const duelQueueJoinHandler = async (req, res) => {
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
};
exports.duelQueueJoin = onRequest(duelQueueJoinHandler);

const duelQueueCancelHandler = async (req, res) => {
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
};
exports.duelQueueCancel = onRequest(duelQueueCancelHandler);

const duelInviteHandler = async (req, res) => {
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
};
exports.duelInvite = onRequest(duelInviteHandler);

const duelRespondHandler = async (req, res) => {
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
};
exports.duelRespond = onRequest(duelRespondHandler);

const duelSubmitAttemptHandler = async (req, res) => {
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
};
exports.duelSubmitAttempt = onRequest(duelSubmitAttemptHandler);

exports.duelQueueJoinV2 = appCheckedDuelCallable("duelQueueJoinV2", duelQueueJoinHandler);
exports.duelQueueCancelV2 = appCheckedDuelCallable("duelQueueCancelV2", duelQueueCancelHandler);
exports.duelInviteV2 = appCheckedDuelCallable("duelInviteV2", duelInviteHandler);
exports.duelRespondV2 = appCheckedDuelCallable("duelRespondV2", duelRespondHandler);
exports.duelSubmitAttemptV2 = appCheckedDuelCallable("duelSubmitAttemptV2", duelSubmitAttemptHandler);

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
        const senderName = String(message.senderName || "Practice buddy").trim();
        const messageText = String(message.text || "").trim();
        logger.info("friend chat message created", {
          threadId,
          messageId: event.params?.messageId || "",
          senderUid,
          recipientUid: String(recipientUid),
        });

        await safePushToUser(String(recipientUid), {
          title: senderName || "New Message",
          body: messageText ? messageText.slice(0, 120) : "You received a new message.",
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
        const messageText = String(message.text || "").trim();
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
          body: messageText ? messageText.slice(0, 120) : "New studio chat message.",
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

async function deleteAccountAndData(uid) {
  const normalizedUID = String(uid || "").trim();
  if (!normalizedUID) {
    throw new Error("Invalid auth user");
  }
  const privateSnapshot = await db.collection("users").doc(normalizedUID).get();
  const handle = String(privateSnapshot.data()?.handle || "").toLowerCase();

  // Best-effort cleanup for user-owned and user-linked data.
  await Promise.allSettled([
    recursiveDeleteDoc(db.collection("users").doc(normalizedUID)),
    recursiveDeleteDoc(db.collection("friendships").doc(normalizedUID)),
    deleteSingleDoc(db.collection("duelQueue").doc(normalizedUID)),
    deleteSingleDoc(db.collection("publicProfiles").doc(normalizedUID)),
    recursiveDeleteDoc(db.collection("feedInboxes").doc(normalizedUID)),
  ]);

  await Promise.allSettled([
    deleteInvitesForUID(normalizedUID),
    deleteBuddyBacklinks(normalizedUID),
    deleteFriendChatsForUID(normalizedUID),
    deleteStudioMembershipsForUID(normalizedUID),
    cancelOpenDuelChallengesForUID(normalizedUID),
    deleteSocialDataForUID(normalizedUID, handle),
  ]);

  try {
    await admin.auth().deleteUser(normalizedUID);
  } catch (error) {
    const code = String(error?.code || "");
    if (code !== "auth/user-not-found") {
      throw error;
    }
  }
}

function parseIdentityInput(body) {
  const displayName = validateDisplayName(body.displayName);
  const handle = validateHandle(body.handle);
  const dateOfBirth = validateDateOfBirth(body.dateOfBirth);
  const instrument = String(body.instrument || "").trim().slice(0, 40);
  if (!instrument) throw new Error("Choose your main instrument.");
  return {
    displayName,
    handle,
    dateOfBirth,
    instrument,
    privacy: parseProfilePrivacy(body.privacy),
  };
}

function validateDisplayName(raw) {
  const value = String(raw || "").normalize("NFC").trim().replace(/\s+/gu, " ");
  if (Array.from(value).length < 2 || Array.from(value).length > 30) {
    throw new Error("Use 2–30 characters for your display name.");
  }
  if (/[\u0000-\u001F\u007F\u202A-\u202E\u2066-\u2069]/u.test(value)) {
    throw new Error("That display name contains unsupported characters.");
  }
  if (!/^[\p{L}\p{N} ._'\-]+$/u.test(value) || !/[\p{L}\p{N}]/u.test(value)) {
    throw new Error("Use letters, numbers, spaces, apostrophes, periods, underscores, or hyphens.");
  }
  if (isBlockedIdentityWord(value)) throw new Error("Choose a different display name.");
  return value;
}

function validateHandle(raw) {
  const value = String(raw || "").trim().toLowerCase();
  if (!/^[a-z0-9](?:[a-z0-9._]*[a-z0-9])?$/.test(value) || value.length < 3 || value.length > 20) {
    throw new Error("Handles use 3–20 lowercase letters, numbers, periods, and underscores.");
  }
  if (/[._]{2}|\._|_\./.test(value) || isBlockedIdentityWord(value)) {
    throw new Error("That handle is unavailable.");
  }
  return value;
}

function validateDateOfBirth(raw) {
  const date = new Date(String(raw || ""));
  if (Number.isNaN(date.getTime()) || date.getTime() > Date.now()) {
    throw new Error("Enter a valid date of birth.");
  }
  const years = ageInYears(date, new Date());
  if (years > 120) throw new Error("Enter a valid date of birth.");
  return date;
}

function parseProfilePrivacy(raw) {
  const value = raw && typeof raw === "object" ? raw : {};
  return {
    isPrivate: value.isPrivate !== false,
    showBio: value.showBio !== false,
    showInstrument: value.showInstrument !== false,
    showPracticeTotals: value.showPracticeTotals === true,
    showMomentsToFollowers: value.showMomentsToFollowers !== false,
  };
}

function isBlockedIdentityWord(value) {
  const canonical = String(value || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
  const reserved = ["admin", "support", "practiquest", "official", "moderator", "system", "staff", "explore", "settings", "you"];
  const blocked = ["fuck", "shit", "bitch", "cunt", "nazi"];
  return reserved.includes(canonical) || blocked.some((word) => canonical.includes(word));
}

function ageInYears(dateOfBirth, now) {
  let age = now.getUTCFullYear() - dateOfBirth.getUTCFullYear();
  const monthDelta = now.getUTCMonth() - dateOfBirth.getUTCMonth();
  if (monthDelta < 0 || (monthDelta === 0 && now.getUTCDate() < dateOfBirth.getUTCDate())) age -= 1;
  return Math.max(0, age);
}

function ageBandForDate(dateOfBirth) {
  const years = ageInYears(dateOfBirth, new Date());
  if (years < 13) return "under13";
  if (years < 18) return "teen";
  return "adult";
}

async function completeIdentityProfile(uid, input, {allowExisting}) {
  const now = new Date();
  const result = await db.runTransaction(async (txn) => {
    const userRef = db.collection("users").doc(uid);
    const userSnap = await txn.get(userRef);
    const current = userSnap.data() || {};
    const existingHandle = String(current.handle || "").toLowerCase();
    if (!allowExisting && Number(current.profileSchemaVersion || 0) >= PROFILE_SCHEMA_VERSION) {
      throw new Error("This profile has already been upgraded.");
    }
    if (existingHandle && existingHandle !== input.handle) {
      const changedAt = current.handleChangedAt?.toDate?.();
      if (changedAt && now.getTime() - changedAt.getTime() < HANDLE_COOLDOWN_MS) {
        throw new Error("Handles can be changed once every 30 days.");
      }
    }
    const handleRef = db.collection("handles").doc(input.handle);
    const handleSnap = await txn.get(handleRef);
    if (handleSnap.exists && String(handleSnap.data()?.uid || "") !== uid) {
      throw new Error("That handle is unavailable.");
    }
    if (existingHandle && existingHandle !== input.handle) {
      txn.delete(db.collection("handles").doc(existingHandle));
      txn.set(db.collection("handleRedirects").doc(existingHandle), {
        uid,
        expiresAt: admin.firestore.Timestamp.fromMillis(now.getTime() + HANDLE_REDIRECT_MS),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    const nextUser = {
      ...current,
      displayName: input.displayName,
      handle: input.handle,
      dateOfBirth: admin.firestore.Timestamp.fromDate(input.dateOfBirth),
      ageBand: ageBandForDate(input.dateOfBirth),
      instrument: input.instrument,
      profilePrivacy: input.privacy,
      profileSchemaVersion: PROFILE_SCHEMA_VERSION,
      handleChangedAt: admin.firestore.Timestamp.fromDate(now),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    txn.set(userRef, nextUser, {merge: true});
    txn.set(handleRef, {uid, createdAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: false});
    txn.set(db.collection("publicProfiles").doc(uid), publicProjectionForUser(nextUser), {merge: true});
    return {handle: input.handle};
  });
  return result;
}

async function changeHandle(uid, handle) {
  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  const current = userSnap.data() || {};
  if (Number(current.profileSchemaVersion || 0) < PROFILE_SCHEMA_VERSION) {
    throw new Error("Finish setting up your profile first.");
  }
  const existingBirthDate = current.dateOfBirth?.toDate?.();
  if (!existingBirthDate) throw new Error("Finish your profile setup before changing a handle.");
  const input = {
    displayName: validateDisplayName(current.displayName),
    handle,
    dateOfBirth: existingBirthDate,
    instrument: String(current.instrument || "").trim(),
    privacy: parseProfilePrivacy(current.profilePrivacy),
  };
  return completeIdentityProfile(uid, input, {allowExisting: true});
}

async function updateIdentityPrivacy(uid, privacy) {
  await db.runTransaction(async (txn) => {
    const userRef = db.collection("users").doc(uid);
    const userSnap = await txn.get(userRef);
    const current = userSnap.data() || {};
    if (Number(current.profileSchemaVersion || 0) < PROFILE_SCHEMA_VERSION) {
      throw new Error("Finish setting up your profile first.");
    }
    const next = {...current, profilePrivacy: privacy};
    txn.set(userRef, {
      profilePrivacy: privacy,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    txn.set(db.collection("publicProfiles").doc(uid), publicProjectionForUser(next), {merge: true});
  });
}

async function createFriendInviteByCode(fromUID, code) {
  const target = await db.collection("users").where("friendCode", "==", code).limit(1).get();
  if (target.empty) throw new Error("No musician found for that code.");
  const targetUID = target.docs[0].id;
  return createFriendInvite(fromUID, targetUID);
}

async function createFriendInvite(fromUID, targetUID) {
  if (targetUID === fromUID) throw new Error("You cannot invite yourself.");
  const inviteRef = db.collection("invites").doc();
  await db.runTransaction(async (txn) => {
    const fromRef = db.collection("users").doc(fromUID);
    const toRef = db.collection("users").doc(targetUID);
    const [fromSnap, toSnap, existingBuddy, outbound, inbound] = await Promise.all([
      txn.get(fromRef),
      txn.get(toRef),
      txn.get(db.collection("friendships").doc(fromUID).collection("buddies").doc(targetUID)),
      txn.get(db.collection("invites").where("fromUid", "==", fromUID).where("toUid", "==", targetUID).where("status", "==", "pending").limit(1)),
      txn.get(db.collection("invites").where("fromUid", "==", targetUID).where("toUid", "==", fromUID).where("status", "==", "pending").limit(1)),
    ]);
    const from = fromSnap.data() || {};
    const to = toSnap.data() || {};
    if (Number(from.profileSchemaVersion || 0) < PROFILE_SCHEMA_VERSION) throw new Error("Finish setting up your profile first.");
    if (Number(to.profileSchemaVersion || 0) < PROFILE_SCHEMA_VERSION) throw new Error("That musician is not ready for friend requests.");
    if (existingBuddy.exists) throw new Error("You are already friends.");
    if (!outbound.empty) throw new Error("A request is already pending.");
    if (!inbound.empty) throw new Error("This musician has already sent you a request.");
    txn.set(inviteRef, {
      fromUid: fromUID,
      toUid: targetUID,
      fromDisplayName: String(from.displayName || "Musician").slice(0, 30),
      fromFriendCode: String(from.friendCode || ""),
      toDisplayName: String(to.displayName || "Musician").slice(0, 30),
      toFriendCode: String(to.friendCode || ""),
      status: "pending",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return {inviteID: inviteRef.id, targetUID};
}

async function applyFriendAction(uid, action, input) {
  await socialActor(uid);
  const allowed = new Set(["invite", "accept", "decline", "cancel", "remove"]);
  if (!allowed.has(action)) throw new Error("That friend action is unavailable.");

  if (action === "invite") {
    const targetUID = validateDocumentID(input.targetUID, "Musician");
    return {...await createFriendInvite(uid, targetUID), status: "pending"};
  }

  if (action === "remove") {
    const targetUID = validateDocumentID(input.targetUID, "Musician");
    if (targetUID === uid) throw new Error("Choose another musician.");

    const myBuddyRef = db.collection("friendships").doc(uid).collection("buddies").doc(targetUID);
    const theirBuddyRef = db.collection("friendships").doc(targetUID).collection("buddies").doc(uid);
    const [myBuddy, theirBuddy, outbound, inbound] = await Promise.all([
      myBuddyRef.get(),
      theirBuddyRef.get(),
      db.collection("invites")
          .where("fromUid", "==", uid)
          .where("toUid", "==", targetUID)
          .where("status", "==", "pending")
          .get(),
      db.collection("invites")
          .where("fromUid", "==", targetUID)
          .where("toUid", "==", uid)
          .where("status", "==", "pending")
          .get(),
    ]);
    if (!myBuddy.exists && !theirBuddy.exists) {
      throw new Error("That friendship is no longer available.");
    }

    const batch = db.batch();
    batch.delete(myBuddyRef);
    batch.delete(theirBuddyRef);
    for (const invite of [...outbound.docs, ...inbound.docs]) {
      batch.update(invite.ref, {
        status: "declined",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return {status: "removed", targetUID};
  }

  const inviteID = validateDocumentID(input.inviteID, "Friend request");
  const inviteRef = db.collection("invites").doc(inviteID);

  return db.runTransaction(async (txn) => {
    const inviteSnap = await txn.get(inviteRef);
    if (!inviteSnap.exists) throw new Error("That friend request is no longer available.");
    const invite = inviteSnap.data() || {};
    if (invite.status !== "pending") throw new Error("That friend request is no longer pending.");

    const fromUID = validateDocumentID(invite.fromUid, "Sender");
    const toUID = validateDocumentID(invite.toUid, "Recipient");
    if (action === "cancel" && uid !== fromUID) {
      throw new Error("Only the sender can cancel this friend request.");
    }
    if ((action === "accept" || action === "decline") && uid !== toUID) {
      throw new Error("Only the recipient can respond to this friend request.");
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    if (action === "decline" || action === "cancel") {
      txn.update(inviteRef, {status: "declined", updatedAt: now});
      return {status: action === "cancel" ? "canceled" : "declined", inviteID};
    }

    const fromRef = db.collection("users").doc(fromUID);
    const toRef = db.collection("users").doc(toUID);
    const [fromSnap, toSnap] = await Promise.all([
      txn.get(fromRef),
      txn.get(toRef),
    ]);
    const from = fromSnap.data() || {};
    const to = toSnap.data() || {};
    if (!fromSnap.exists || !toSnap.exists) {
      throw new Error("One of these profiles is no longer available.");
    }

    txn.update(inviteRef, {status: "accepted", updatedAt: now});
    txn.set(
        db.collection("friendships").doc(toUID).collection("buddies").doc(fromUID),
        friendProjection(fromUID, from, now),
        {merge: true},
    );
    txn.set(
        db.collection("friendships").doc(fromUID).collection("buddies").doc(toUID),
        friendProjection(toUID, to, now),
        {merge: true},
    );
    return {status: "accepted", inviteID, targetUID: fromUID};
  });
}

function friendProjection(uid, user, sinceAt) {
  return {
    buddyUid: uid,
    displayName: String(user.displayName || "Musician").slice(0, 30),
    friendCode: String(user.friendCode || "").slice(0, 32),
    avatarID: String(user.avatarID || "avatar_note").slice(0, 64),
    profilePhotoURL: String(user.profilePhotoURL || "").slice(0, 2048),
    publicLevel: clampInt(user.publicLevel, 1, 1000000, 1),
    sinceAt,
  };
}

function publicProjectionForUser(user) {
  const privacy = parseProfilePrivacy(user.profilePrivacy);
  return {
    displayName: String(user.displayName || "Musician").slice(0, 30),
    handle: String(user.handle || "").toLowerCase(),
    profilePhotoURL: String(user.profilePhotoURL || "").slice(0, 2048),
    instrument: privacy.showInstrument ? String(user.instrument || "Musician").slice(0, 40) : "Musician",
    bio: privacy.showBio ? String(user.bio || "").slice(0, 160) : "",
    publicLevel: clampInt(user.publicLevel, 1, 1000000, 1),
    duelLeague: String(user.duelLeague || "bronze").slice(0, 24),
    duelRating: clampInt(user.duelRating, 0, 1000000, 0),
    avatarID: String(user.avatarID || "avatar_note").slice(0, 64),
    isPrivate: privacy.isPrivate,
    allowsMoments: user.ageBand !== "under13" && privacy.showMomentsToFollowers,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

function socialDocID(uidA, uidB) {
  return `${uidA}_${uidB}`;
}

function socialReason(raw) {
  const value = String(raw || "other");
  const allowed = new Set(["spam", "harassment", "impersonation", "unsafe", "other"]);
  return allowed.has(value) ? value : "other";
}

async function socialActor(uid) {
  const snap = await db.collection("users").doc(uid).get();
  const user = snap.data() || {};
  if (Number(user.profileSchemaVersion || 0) < PROFILE_SCHEMA_VERSION) {
    throw new Error("Finish setting up your profile first.");
  }
  if (user.ageBand === "under13") {
    throw new Error("Community actions are not available for this account.");
  }
  return user;
}

async function applySocialAction(uid, targetUID, action, reason) {
  if (uid === targetUID) throw new Error("Choose another musician.");
  const allowed = new Set([
    "follow", "unfollow", "acceptFollow", "declineFollow", "removeFollower",
    "block", "unblock", "reportProfile", "reportMoment", "mute",
  ]);
  if (!allowed.has(action)) throw new Error("That community action is unavailable.");

  const [actor, targetSnap] = await Promise.all([
    socialActor(uid),
    db.collection("users").doc(targetUID).get(),
  ]);
  const target = targetSnap.data() || {};
  if (!targetSnap.exists || Number(target.profileSchemaVersion || 0) < PROFILE_SCHEMA_VERSION) {
    throw new Error("That musician is unavailable.");
  }
  if (target.ageBand === "under13") throw new Error("That musician is unavailable.");

  const followRef = db.collection("socialFollows").doc(socialDocID(uid, targetUID));
  const inverseFollowRef = db.collection("socialFollows").doc(socialDocID(targetUID, uid));
  const requestRef = db.collection("followRequests").doc(socialDocID(uid, targetUID));
  const inverseRequestRef = db.collection("followRequests").doc(socialDocID(targetUID, uid));
  const blockRef = db.collection("socialBlocks").doc(socialDocID(uid, targetUID));
  const inverseBlockRef = db.collection("socialBlocks").doc(socialDocID(targetUID, uid));
  const now = admin.firestore.FieldValue.serverTimestamp();

  if (action === "reportProfile" || action === "reportMoment") {
    await db.collection("contentReports").doc().set({
      reporterUID: uid,
      targetUID,
      targetType: action === "reportMoment" ? "moment" : "profile",
      targetID: String(reason?.targetID || targetUID).slice(0, 128),
      reason: socialReason(reason?.kind || reason),
      createdAt: now,
    });
    return {status: "reported"};
  }

  if (action === "mute") {
    await db.collection("socialMutes").doc(socialDocID(uid, targetUID)).set({
      ownerUID: uid, targetUID, createdAt: now,
    }, {merge: true});
    return {status: "muted"};
  }

  if (action === "block") {
    const batch = db.batch();
    batch.set(blockRef, {blockerUID: uid, blockedUID: targetUID, createdAt: now});
    batch.delete(followRef);
    batch.delete(inverseFollowRef);
    batch.delete(requestRef);
    batch.delete(inverseRequestRef);
    await batch.commit();
    return {status: "blocked"};
  }
  if (action === "unblock") {
    await blockRef.delete();
    return {status: "unblocked"};
  }

  const [blockedByMe, blockedByTarget] = await Promise.all([blockRef.get(), inverseBlockRef.get()]);
  if (blockedByMe.exists || blockedByTarget.exists) throw new Error("This community action is unavailable.");

  if (action === "follow") {
    const needsApproval = target.ageBand === "teen" || parseProfilePrivacy(target.profilePrivacy).isPrivate;
    if (needsApproval) {
      await requestRef.set({
        fromUID: uid, toUID: targetUID, createdAt: now, updatedAt: now,
      }, {merge: true});
      return {status: "requested"};
    }
    await followRef.set({
      fromUID: uid, toUID: targetUID, status: "following", createdAt: now, acceptedAt: now,
    }, {merge: true});
    return {status: "following"};
  }
  if (action === "unfollow" || action === "removeFollower") {
    const ref = action === "unfollow" ? followRef : inverseFollowRef;
    const pending = action === "unfollow" ? requestRef : inverseRequestRef;
    await Promise.allSettled([ref.delete(), pending.delete()]);
    return {status: action === "unfollow" ? "unfollowed" : "removed"};
  }
  if (action === "acceptFollow") {
    const incoming = await inverseRequestRef.get();
    if (!incoming.exists) throw new Error("That follow request is no longer available.");
    const batch = db.batch();
    batch.delete(inverseRequestRef);
    batch.set(inverseFollowRef, {
      fromUID: targetUID, toUID: uid, status: "following", createdAt: incoming.data()?.createdAt || now, acceptedAt: now,
    });
    await batch.commit();
    return {status: "following"};
  }
  if (action === "declineFollow") {
    await inverseRequestRef.delete();
    return {status: "declined"};
  }
  throw new Error("That community action is unavailable.");
}

async function socialRelationshipState(uid, targetUID) {
  if (uid === targetUID) return "none";
  await socialActor(uid);

  const [
    blockedByMe,
    outgoingFollow,
    incomingFollow,
    outgoingRequest,
  ] = await Promise.all([
    db.collection("socialBlocks").doc(socialDocID(uid, targetUID)).get(),
    db.collection("socialFollows").doc(socialDocID(uid, targetUID)).get(),
    db.collection("socialFollows").doc(socialDocID(targetUID, uid)).get(),
    db.collection("followRequests").doc(socialDocID(uid, targetUID)).get(),
  ]);

  if (blockedByMe.exists) return "blocked";
  if (outgoingFollow.exists && incomingFollow.exists) return "mutualFollowing";
  if (outgoingFollow.exists) return "following";
  if (outgoingRequest.exists) return "requested";
  if (incomingFollow.exists) return "followsYou";
  return "none";
}

async function socialConnectionRows(uid, section) {
  const valid = new Set(["following", "followers", "requests"]);
  if (!valid.has(section)) throw new Error("That connection section is unavailable.");
  await socialActor(uid);
  let snapshot;
  let profileIDs = [];
  if (section === "following") {
    snapshot = await db.collection("socialFollows").where("fromUID", "==", uid).where("status", "==", "following").limit(100).get();
    profileIDs = snapshot.docs.map((doc) => String(doc.data()?.toUID || ""));
  } else if (section === "followers") {
    snapshot = await db.collection("socialFollows").where("toUID", "==", uid).where("status", "==", "following").limit(100).get();
    profileIDs = snapshot.docs.map((doc) => String(doc.data()?.fromUID || ""));
  } else {
    const [incoming, outgoing] = await Promise.all([
      db.collection("followRequests").where("toUID", "==", uid).limit(100).get(),
      db.collection("followRequests").where("fromUID", "==", uid).limit(100).get(),
    ]);
    snapshot = {docs: [...incoming.docs, ...outgoing.docs]};
    profileIDs = snapshot.docs.map((doc) => {
      const data = doc.data() || {};
      return String(data.fromUID === uid ? data.toUID : data.fromUID || "");
    });
  }
  const profiles = await Promise.all(profileIDs.filter(Boolean).map(async (id) => {
    const doc = await db.collection("publicProfiles").doc(id).get();
    const data = doc.data() || {};
    return {
      id,
      displayName: String(data.displayName || "Musician"),
      handle: String(data.handle || ""),
      profilePhotoURL: String(data.profilePhotoURL || ""),
      instrument: String(data.instrument || "Musician"),
      avatarID: String(data.avatarID || "avatar_note"),
      isIncoming: section === "requests" && snapshot.docs.find((item) => item.data()?.fromUID === id) != null,
    };
  }));
  return profiles;
}

function parseMomentInput(body) {
  const sessionID = validateDocumentID(body.sessionID, "Session");
  const durationSeconds = clampInt(body.durationSeconds, 300, 8 * 60 * 60, 0);
  if (durationSeconds < 300) throw new Error("Practice for at least five minutes before sharing a Moment.");
  const tag = String(body.tag || "");
  if (!VALID_MOMENT_TAGS.has(tag)) throw new Error("Choose a valid Moment tag.");
  const audience = String(body.audience || "");
  if (!VALID_MOMENT_AUDIENCES.has(audience)) {
    throw new Error("Moments can be shared with Friends or Following.");
  }
  const categories = new Set(["Focused practice", "Warm-up", "Technique", "Rhythm", "Intonation", "Run-through", "Performance prep"]);
  const practiceCategory = String(body.practiceCategory || "Focused practice");
  if (!categories.has(practiceCategory)) throw new Error("Choose a valid practice category.");
  return {
    sessionID,
    durationSeconds,
    tag,
    audience,
    practiceCategory,
    isVerified: body.isVerified === true,
    localDayKey: validateMomentDayKey(body.localDayKey),
    avatarLoadout: sanitizeAvatarLoadout(body.avatarLoadout),
  };
}

function validateMomentDayKey(raw) {
  const value = String(raw || "");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error("Moment day is invalid.");
  const provided = new Date(`${value}T12:00:00Z`);
  if (Number.isNaN(provided.getTime())) throw new Error("Moment day is invalid.");
  // A device can be near a date boundary; accept the user’s local today plus
  // one adjacent UTC day, but do not allow a client to mint arbitrary daily IDs.
  const now = new Date();
  if (Math.abs(provided.getTime() - Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), 12)) > 36 * 60 * 60 * 1000) {
    throw new Error("Moment day is invalid.");
  }
  return value;
}

function validateDocumentID(value, label) {
  const id = String(value || "").trim();
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(id)) throw new Error(`${label} is invalid.`);
  return id;
}

function sanitizeAvatarLoadout(value) {
  const raw = value && typeof value === "object" ? value : {};
  const allowedRooms = new Set(["room_daylight_studio", "room_midnight_stage", "room_creative_loft"]);
  const allowedDecorations = new Set([
    "room_decoration_plant", "room_decoration_rug", "room_decoration_lamp", "room_decoration_art", "room_decoration_shelf",
  ]);
  const roomID = allowedRooms.has(String(raw.roomID || "")) ? String(raw.roomID) : "room_daylight_studio";
  const stringField = (key, fallback) => {
    const candidate = String(raw[key] || "").trim();
    return /^[A-Za-z0-9_.-]{1,64}$/.test(candidate) ? candidate : fallback;
  };
  const roomLayouts = {};
  const layouts = raw.roomLayouts && typeof raw.roomLayouts === "object" ? raw.roomLayouts : {};
  for (const [key, layout] of Object.entries(layouts)) {
    if (!allowedRooms.has(key) || !layout || typeof layout !== "object") continue;
    const placements = Array.isArray(layout.placements) ? layout.placements.slice(0, 30) : [];
    roomLayouts[key] = {
      roomID: key,
      placements: placements.map((placement) => {
        const position = placement?.position && typeof placement.position === "object" ? placement.position : {};
        const decorationID = allowedDecorations.has(String(placement?.decorationID || "")) ? String(placement.decorationID) : "room_decoration_plant";
        return {
          id: /^[A-Za-z0-9_-]{8,128}$/.test(String(placement?.id || "")) ? String(placement.id) : admin.firestore().collection("_ids").doc().id,
          decorationID,
          position: {
            x: clampNumber(position.x, 0.06, 0.94, 0.5),
            y: clampNumber(position.y, 0.14, 0.92, 0.72),
          },
          scale: clampNumber(placement?.scale, 0.7, 1.4, 1),
          rotationDegrees: clampNumber(placement?.rotationDegrees, -8, 8, 0),
          depth: clampInt(placement?.depth, -10, 10, 0),
        };
      }),
    };
  }
  return {
    version: 2,
    baseID: stringField("baseID", "avatar_note"),
    skinToneID: stringField("skinToneID", "tone_3"),
    hairID: stringField("hairID", "hair_short"),
    outfitID: stringField("outfitID", "outfit_studio"),
    instrumentID: stringField("instrumentID", "instrument_music"),
    accessoryID: raw.accessoryID == null ? null : stringField("accessoryID", ""),
    poseID: stringField("poseID", "idle"),
    roomID,
    roomLayouts,
  };
}

function clampNumber(value, min, max, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(max, Math.max(min, number));
}

function momentDurationBucket(seconds) {
  if (seconds < 15 * 60) return "5–14 min";
  if (seconds < 30 * 60) return "15–29 min";
  if (seconds < 60 * 60) return "30–59 min";
  return "60+ min";
}

async function createPracticeMoment(uid, input) {
  const now = new Date();
  const uniqueID = `${uid}_${input.localDayKey}`;
  const momentRef = db.collection("practiceMoments").doc(uniqueID);
  const userRef = db.collection("users").doc(uid);
  const profileRef = db.collection("publicProfiles").doc(uid);
  const expiresAt = admin.firestore.Timestamp.fromMillis(now.getTime() + MOMENT_LIFETIME_MS);
  const profile = await db.runTransaction(async (txn) => {
    const [userSnap, publicSnap, existing] = await Promise.all([txn.get(userRef), txn.get(profileRef), txn.get(momentRef)]);
    const user = userSnap.data() || {};
    if (Number(user.profileSchemaVersion || 0) < PROFILE_SCHEMA_VERSION) {
      throw new Error("Finish your profile upgrade before sharing a Moment.");
    }
    if (user.ageBand === "under13") throw new Error("Moments are not available for this account.");
    if (existing.exists && existing.data()?.expiresAt?.toDate?.() > now) {
      throw new Error("You can share one Practice Moment per day.");
    }
    const projection = publicSnap.data() || publicProjectionForUser(user);
    const moment = {
      authorUID: uid,
      displayName: String(projection.displayName || "Musician"),
      handle: String(projection.handle || ""),
      profilePhotoURL: String(projection.profilePhotoURL || ""),
      instrument: String(projection.instrument || "Musician"),
      durationBucket: momentDurationBucket(input.durationSeconds),
      practiceCategory: input.practiceCategory,
      isVerified: input.isVerified,
      tag: input.tag,
      audience: input.audience,
      avatarLoadout: input.avatarLoadout,
      moderationState: "active",
      reactionCounts: {},
      sessionID: input.sessionID,
      localDayKey: input.localDayKey,
      createdAt: admin.firestore.Timestamp.fromDate(now),
      expiresAt,
    };
    txn.set(momentRef, moment);
    return projection;
  });

  const recipients = await momentRecipients(uid, input.audience);
  const uniqueRecipients = Array.from(new Set([uid, ...recipients])).slice(0, MAX_MOMENT_FANOUT);
  const batch = db.batch();
  for (const recipientUID of uniqueRecipients) {
    batch.set(db.collection("feedInboxes").doc(recipientUID).collection("items").doc(uniqueID), {
      momentID: uniqueID,
      authorUID: uid,
      createdAt: admin.firestore.Timestamp.fromDate(now),
      expiresAt,
    });
  }
  await batch.commit();
  logger.info("practice Moment created", {uid, audience: input.audience, recipients: uniqueRecipients.length});
  return {momentID: uniqueID, recipientCount: uniqueRecipients.length, handle: profile.handle};
}

async function momentRecipients(uid, audience) {
  if (audience === "friends") {
    const buddies = await db.collection("friendships").doc(uid).collection("buddies").limit(MAX_MOMENT_FANOUT).get();
    return buddies.docs.map((doc) => doc.id).filter(Boolean);
  }
  const follows = await db.collection("socialFollows")
      .where("toUID", "==", uid)
      .where("status", "==", "following")
      .limit(MAX_MOMENT_FANOUT)
      .get();
  return follows.docs.map((doc) => String(doc.data()?.fromUID || "")).filter(Boolean);
}

async function reactToPracticeMoment(uid, momentID, reaction) {
  const momentRef = db.collection("practiceMoments").doc(momentID);
  const reactionRef = momentRef.collection("reactions").doc(uid);
  await db.runTransaction(async (txn) => {
    const momentSnap = await txn.get(momentRef);
    if (!momentSnap.exists) throw new Error("This Moment is unavailable.");
    const moment = momentSnap.data() || {};
    if (moment.moderationState !== "active" || moment.expiresAt?.toDate?.() <= new Date()) {
      throw new Error("This Moment is no longer available.");
    }
    const ownerUID = String(moment.authorUID || "");
    const inInbox = uid === ownerUID || (await txn.get(db.collection("feedInboxes").doc(uid).collection("items").doc(momentID))).exists;
    if (!inInbox) throw new Error("You do not have access to this Moment.");
    const prior = await txn.get(reactionRef);
    const previousKind = String(prior.data()?.kind || "");
    const counts = {...(moment.reactionCounts || {})};
    if (previousKind && VALID_MOMENT_REACTIONS.has(previousKind)) {
      counts[previousKind] = Math.max(0, Number(counts[previousKind] || 0) - 1);
    }
    counts[reaction] = Math.max(0, Number(counts[reaction] || 0)) + 1;
    txn.set(reactionRef, {kind: reaction, updatedAt: admin.firestore.FieldValue.serverTimestamp()});
    txn.update(momentRef, {reactionCounts: counts, updatedAt: admin.firestore.FieldValue.serverTimestamp()});
  });
}

async function deletePracticeMomentEverywhere(momentID) {
  const itemDocs = await db.collectionGroup("items").where("momentID", "==", momentID).limit(600).get();
  await deleteDocSnapshots(itemDocs.docs);
  await recursiveDeleteDoc(db.collection("practiceMoments").doc(momentID));
}

async function deleteSocialDataForUID(uid, knownHandle = "") {
  const handle = String(knownHandle || "").toLowerCase();
  const moments = await db.collection("practiceMoments").where("authorUID", "==", uid).limit(500).get();
  const outgoingFollows = await db.collection("socialFollows").where("fromUID", "==", uid).limit(500).get();
  const incomingFollows = await db.collection("socialFollows").where("toUID", "==", uid).limit(500).get();
  const outgoingRequests = await db.collection("followRequests").where("fromUID", "==", uid).limit(500).get();
  const incomingRequests = await db.collection("followRequests").where("toUID", "==", uid).limit(500).get();
  const outgoingBlocks = await db.collection("socialBlocks").where("blockerUID", "==", uid).limit(500).get();
  const incomingBlocks = await db.collection("socialBlocks").where("blockedUID", "==", uid).limit(500).get();
  const ownedMutes = await db.collection("socialMutes").where("ownerUID", "==", uid).limit(500).get();
  const targetMutes = await db.collection("socialMutes").where("targetUID", "==", uid).limit(500).get();
  await Promise.allSettled([
    ...moments.docs.map((doc) => deletePracticeMomentEverywhere(doc.id)),
    deleteDocSnapshots([
      ...outgoingFollows.docs, ...incomingFollows.docs,
      ...outgoingRequests.docs, ...incomingRequests.docs,
      ...outgoingBlocks.docs, ...incomingBlocks.docs,
      ...ownedMutes.docs, ...targetMutes.docs,
    ]),
    handle ? deleteSingleDoc(db.collection("handles").doc(handle)) : Promise.resolve(),
  ]);
  if (handle) await deleteSingleDoc(db.collection("handleRedirects").doc(handle));
}

async function recursiveDeleteDoc(docRef) {
  try {
    await db.recursiveDelete(docRef);
  } catch (error) {
    logger.warn("recursive delete failed", {path: docRef.path, error: String(error?.message || error)});
  }
}

async function deleteSingleDoc(docRef) {
  try {
    await docRef.delete();
  } catch (error) {
    logger.warn("single delete failed", {path: docRef.path, error: String(error?.message || error)});
  }
}

async function deleteInvitesForUID(uid) {
  const outbound = await db.collection("invites").where("fromUid", "==", uid).get();
  const inbound = await db.collection("invites").where("toUid", "==", uid).get();
  await deleteDocSnapshots([...outbound.docs, ...inbound.docs]);
}

async function deleteBuddyBacklinks(uid) {
  const buddyBacklinks = await db.collectionGroup("buddies")
      .where(admin.firestore.FieldPath.documentId(), "==", uid)
      .get();
  await deleteDocSnapshots(buddyBacklinks.docs);
}

async function deleteFriendChatsForUID(uid) {
  const chats = await db.collection("friendChats")
      .where("participants", "array-contains", uid)
      .get();
  await Promise.allSettled(chats.docs.map((doc) => db.recursiveDelete(doc.ref)));
}

async function deleteStudioMembershipsForUID(uid) {
  const memberDocs = await db.collectionGroup("members")
      .where(admin.firestore.FieldPath.documentId(), "==", uid)
      .get();

  for (const memberDoc of memberDocs.docs) {
    const studioRef = memberDoc.ref.parent.parent;
    if (!studioRef) continue;

    try {
      const studioSnap = await studioRef.get();
      const ownerUID = String(studioSnap.data()?.ownerUid || "");
      if (ownerUID === uid) {
        await db.recursiveDelete(studioRef);
      } else {
        await memberDoc.ref.delete();
      }
    } catch (error) {
      logger.warn("studio membership cleanup failed", {
        path: memberDoc.ref.path,
        error: String(error?.message || error),
      });
    }
  }
}

async function cancelOpenDuelChallengesForUID(uid) {
  const challenges = await db.collection("duelChallenges")
      .where("participants", "array-contains", uid)
      .get();
  const updates = challenges.docs
      .filter((doc) => {
        const status = String(doc.data()?.status || "");
        return status === "open" || status === "invited" || status === "active";
      })
      .map((doc) => doc.ref.set({
        status: "canceled",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true}));

  await Promise.allSettled(updates);
}

async function deleteDocSnapshots(docs) {
  if (!Array.isArray(docs) || docs.length === 0) return;
  await Promise.allSettled(docs.map((doc) => doc.ref.delete()));
}

async function requireUID(req) {
  return (await requireAuth(req)).uid;
}

async function requireAuth(req) {
  const internalAuth = req[INTERNAL_CALLABLE_AUTH];
  if (internalAuth?.uid) {
    return {uid: internalAuth.uid, token: internalAuth.token || {}};
  }
  const authHeader = req.get("Authorization") || "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.substring(7) : "";
  if (!token) throw new Error("Missing auth token");
  const decoded = await admin.auth().verifyIdToken(token);
  const uid = String(decoded.uid || "").trim();
  if (!uid) throw new Error("Invalid auth user");
  return {uid, token: decoded};
}

function requireCallablePermanentAuth(request) {
  const auth = requireCallableAuth(request);
  if (auth.token?.firebase?.sign_in_provider === "anonymous") {
    throw new HttpsError(
        "failed-precondition",
        "Create a permanent profile before using community features.",
    );
  }
  return auth;
}

function requireCallableAuth(request) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in to continue.");
  }
  return request.auth;
}

function asCallableError(error) {
  if (error instanceof HttpsError) return error;
  const message = String(error?.message || "The service is unavailable right now.");
  return new HttpsError("failed-precondition", message);
}

function appCheckedDuelCallable(name, handler) {
  return onCall(
      {enforceAppCheck: true, maxInstances: 5},
      async (request) => {
        try {
          const auth = requireCallablePermanentAuth(request);
          return await invokeSharedHTTPHandler(handler, request.data || {}, auth);
        } catch (error) {
          logger.warn(`${name} failed`, {error: String(error?.message || error)});
          throw asCallableError(error);
        }
      },
  );
}

async function invokeSharedHTTPHandler(handler, body, auth) {
  let statusCode = 200;
  let responsePayload = null;
  const request = {
    method: "POST",
    body,
    [INTERNAL_CALLABLE_AUTH]: auth,
    get: () => "",
  };
  const response = {
    status(code) {
      statusCode = Number(code) || 500;
      return this;
    },
    json(payload) {
      responsePayload = payload;
      return this;
    },
  };

  await handler(request, response);
  if (statusCode < 200 || statusCode >= 300) {
    throw new Error(
        String(responsePayload?.error || `The duel service failed (${statusCode}).`),
    );
  }
  if (!responsePayload || responsePayload.ok !== true) {
    throw new Error("The duel service returned an invalid response.");
  }
  return responsePayload;
}

async function sendPushTestNotification(uid, input) {
  const route = String(input?.route || ROUTE_SOCIAL_CHAT).trim().toLowerCase();
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
      challengeId: String(input?.challengeId || ""),
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

  const result = await pushToUser(uid, {title, body, prefKey, data, category});
  if (result.sent) return result;

  const detail = result.failureCodes?.length
    ? `Firebase failure codes: ${result.failureCodes.join(", ")}`
    : result.detail || null;
  const error = new Error(
      `Push test was not delivered: ${result.reason}${detail ? ` (${detail})` : ""}`,
  );
  error.reason = result.reason;
  error.detail = detail;
  error.failureCodes = result.failureCodes || [];
  throw error;
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
    return await pushToUser(uid, {title, body, prefKey, data, category});
  } catch (error) {
    logger.warn("push notification failed", {uid, error: String(error?.message || error)});
    return {sent: false, reason: "send_error", detail: String(error?.message || error)};
  }
}

async function pushToUser(uid, {title, body, prefKey, data, category}) {
  const normalizedUid = String(uid || "").trim();
  if (!normalizedUid) return {sent: false, reason: "missing_uid"};

  const userSnap = await db.collection("users").doc(normalizedUid).get();
  if (!userSnap.exists) {
    logger.warn("push skipped: user document missing", {uid: normalizedUid});
    return {sent: false, reason: "missing_user"};
  }
  const userData = userSnap.data() || {};
  if (prefKey && userData[prefKey] === false) {
    logger.info("push skipped: notification preference disabled", {uid: normalizedUid, prefKey});
    return {sent: false, reason: "preference_disabled", detail: prefKey};
  }

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
  if (tokenRows.length === 0) {
    logger.warn("push skipped: no device tokens stored for user", {uid: normalizedUid});
    return {sent: false, reason: "no_device_tokens"};
  }
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
    return {
      sent: false,
      reason: "no_fcm_tokens",
      detail: `stored token types: ${Array.from(new Set(tokenRows.map((row) => row.tokenType || "legacy"))).join(", ")}`,
    };
  }

  const payloadData = normalizePushData(data);
  const previousBadge = clampInt(userData.notificationBadgeCount, 0, 99, 0);
  const badge = clampInt(previousBadge + 1, 1, 99, 1);
  logger.info("sending push notification", {
    uid: normalizedUid,
    tokenCount: tokens.length,
    prefKey: prefKey || "",
    category: category || "",
  });
  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {
      title: String(title || "PractiQuest"),
      body: String(body || ""),
    },
    data: payloadData,
    apns: {
      headers: {
        "apns-priority": "10",
      },
      payload: {
        aps: {
          alert: {
            title: String(title || "PractiQuest"),
            body: String(body || ""),
          },
          sound: "default",
          category: String(category || ""),
          badge,
        },
      },
    },
  });
  logger.info("push send result", {
    uid: normalizedUid,
    successCount: response.successCount,
    failureCount: response.failureCount,
    failureCodes: response.responses
        .filter((result) => result && result.error)
        .map((result) => String(result.error.code || "unknown"))
        .slice(0, 5),
  });
  await pruneInvalidDeviceTokens(normalizedUid, tokens, response.responses);
  if (response.successCount > 0) {
    await db.collection("users").doc(normalizedUid).set({
      notificationBadgeCount: badge,
      notificationBadgeUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  return {
    sent: response.successCount > 0,
    reason: response.successCount > 0 ? "sent" : "all_tokens_failed",
    successCount: response.successCount,
    failureCount: response.failureCount,
    failureCodes: Array.from(new Set(response.responses
        .filter((result) => result && result.error)
        .map((result) => String(result.error.code || "unknown")))),
    badge,
  };
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
