"use strict";

const assert = require("node:assert/strict");
const {
  RateLimitError,
  consumeRateLimit,
  nextRateLimitState,
} = require("../lib/rate-limit");

describe("PractiQuest callable rate limits", () => {
  it("increments inside a window and rejects after the budget", () => {
    const start = 1_000;
    const first = nextRateLimitState({}, start, 2, 60_000);
    const second = nextRateLimitState(first.state, start + 10, 2, 60_000);
    const rejected = nextRateLimitState(second.state, start + 20, 2, 60_000);

    assert.equal(first.allowed, true);
    assert.equal(second.allowed, true);
    assert.equal(second.state.count, 2);
    assert.equal(rejected.allowed, false);
    assert.equal(rejected.retryAfterMs, 59_980);
  });

  it("starts a clean window after expiry or a future timestamp", () => {
    const expired = nextRateLimitState(
        {windowStartedAtMs: 1_000, count: 99},
        61_000,
        2,
        60_000,
    );
    const future = nextRateLimitState(
        {windowStartedAtMs: 100_000, count: 99},
        50_000,
        2,
        60_000,
    );

    assert.deepEqual(expired.state, {windowStartedAtMs: 61_000, count: 1});
    assert.deepEqual(future.state, {windowStartedAtMs: 50_000, count: 1});
  });

  it("persists only allowed attempts and returns resource-exhausted", async () => {
    let stored = null;
    const db = fakeDatabase({
      read: () => stored,
      write: (value) => {
        stored = value;
      },
    });

    await consumeRateLimit({
      db,
      uid: "user-1",
      action: "friend_invite",
      limit: 1,
      windowMs: 60_000,
      nowMs: 2_000,
    });

    await assert.rejects(
        consumeRateLimit({
          db,
          uid: "user-1",
          action: "friend_invite",
          limit: 1,
          windowMs: 60_000,
          nowMs: 2_100,
        }),
        (error) => {
          assert.equal(error instanceof RateLimitError, true);
          assert.equal(error.callableCode, "resource-exhausted");
          assert.equal(error.retryAfterSeconds, 60);
          return true;
        },
    );
    assert.equal(stored.count, 1);
  });
});

function fakeDatabase({read, write}) {
  return {
    collection() {
      return {
        doc() {
          return {id: "rate-limit"};
        },
      };
    },
    async runTransaction(operation) {
      return operation({
        async get() {
          const value = read();
          return {
            data: () => value,
          };
        },
        set(_reference, value) {
          write(value);
        },
      });
    },
  };
}

