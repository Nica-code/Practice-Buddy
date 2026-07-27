"use strict";

class RateLimitError extends Error {
  constructor(retryAfterSeconds) {
    super("Too many requests. Wait a moment and try again.");
    this.name = "RateLimitError";
    this.callableCode = "resource-exhausted";
    this.retryAfterSeconds = Math.max(1, Math.ceil(retryAfterSeconds));
  }
}

function nextRateLimitState(current, nowMs, limit, windowMs) {
  if (!Number.isFinite(nowMs) || !Number.isFinite(limit) ||
      !Number.isFinite(windowMs) || limit < 1 || windowMs < 1) {
    throw new TypeError("Rate-limit inputs must be positive finite numbers.");
  }

  const priorStart = Number(current?.windowStartedAtMs);
  const priorCount = Math.max(0, Math.floor(Number(current?.count) || 0));
  const priorWindowIsValid = Number.isFinite(priorStart) &&
    nowMs >= priorStart &&
    nowMs < priorStart + windowMs;
  const windowStartedAtMs = priorWindowIsValid ? priorStart : nowMs;
  const count = priorWindowIsValid ? priorCount : 0;

  if (count >= limit) {
    return {
      allowed: false,
      retryAfterMs: Math.max(1, windowStartedAtMs + windowMs - nowMs),
      state: {
        windowStartedAtMs,
        count,
      },
    };
  }

  return {
    allowed: true,
    retryAfterMs: 0,
    state: {
      windowStartedAtMs,
      count: count + 1,
    },
  };
}

async function consumeRateLimit({
  db,
  uid,
  action,
  limit,
  windowMs,
  nowMs = Date.now(),
}) {
  const normalizedUID = String(uid || "").trim();
  const normalizedAction = String(action || "").trim();
  if (!normalizedUID || !/^[A-Za-z0-9_-]{1,80}$/.test(normalizedAction)) {
    throw new TypeError("A valid user and server-owned action are required.");
  }

  const reference = db.collection("rateLimits")
      .doc(`${normalizedUID}_${normalizedAction}`);
  const decision = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const next = nextRateLimitState(
        snapshot.data() || {},
        nowMs,
        limit,
        windowMs,
    );
    if (next.allowed) {
      transaction.set(reference, {
        uid: normalizedUID,
        action: normalizedAction,
        ...next.state,
        updatedAt: new Date(nowMs),
        expiresAt: new Date(next.state.windowStartedAtMs + (windowMs * 2)),
      });
    }
    return next;
  });

  if (!decision.allowed) {
    throw new RateLimitError(decision.retryAfterMs / 1000);
  }
  return decision.state;
}

module.exports = {
  RateLimitError,
  consumeRateLimit,
  nextRateLimitState,
};

