const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const { consume, checkRateLimit, POLICIES } = require("../lib/rateLimit");

const POLICY = { limit: 3, windowMs: 1000 };

describe("consume", () => {
  test("allows up to the limit within one window, then refuses", () => {
    let state;
    for (let i = 1; i <= 3; i++) {
      const result = consume(state, 100, POLICY);
      assert.equal(result.allowed, true);
      assert.equal(result.next.count, i);
      state = result.next;
    }
    const refused = consume(state, 400, POLICY);
    assert.equal(refused.allowed, false);
    // Window opened at t=100, so it reopens at t=1100.
    assert.equal(refused.retryAfterMs, 700);
  });

  test("starts a fresh window once the old one has elapsed", () => {
    const spent = { windowStart: 0, count: 3 };
    const result = consume(spent, 1000, POLICY);
    assert.equal(result.allowed, true);
    assert.deepEqual(result.next, { windowStart: 1000, count: 1 });
  });

  test("treats corrupt stored state as no state", () => {
    const result = consume({ windowStart: "x", count: 99 }, 5, POLICY);
    assert.equal(result.allowed, true);
    assert.equal(result.next.count, 1);
  });
});

/**
 * A single-document in-memory stand-in for Firestore's transaction API -
 * just what checkRateLimit touches.
 * @param {object} opts
 * @return {object} Fake db.
 */
function fakeDb({ fail = false } = {}) {
  const docs = new Map();
  return {
    docs,
    collection: (name) => ({
      doc: (id) => ({ path: `${name}/${id}` }),
    }),
    runTransaction: async (fn) => {
      if (fail) throw new Error("firestore unavailable");
      return fn({
        get: async (ref) => ({
          exists: docs.has(ref.path),
          data: () => docs.get(ref.path),
        }),
        set: (ref, data) => docs.set(ref.path, data),
      });
    },
  };
}

describe("checkRateLimit", () => {
  test("keeps separate budgets per user and per policy", async () => {
    const db = fakeDb();
    const { limit } = POLICIES.mpesaPush;
    for (let i = 0; i < limit; i++) {
      assert.equal((await checkRateLimit("mpesaPush", "u1", { db, now: 0 })).allowed, true);
    }
    assert.equal((await checkRateLimit("mpesaPush", "u1", { db, now: 0 })).allowed, false);
    assert.equal((await checkRateLimit("mpesaPush", "u2", { db, now: 0 })).allowed, true);
    assert.equal((await checkRateLimit("createOrder", "u1", { db, now: 0 })).allowed, true);
  });

  test("stamps expireAt for the Firestore TTL policy", async () => {
    const db = fakeDb();
    await checkRateLimit("createOrder", "u1", { db, now: 5000 });
    const stored = db.docs.get("rate_limits/createOrder_u1");
    assert.equal(stored.expireAt.toMillis(), 5000 + POLICIES.createOrder.windowMs);
  });

  test("fails open when Firestore itself errors", async () => {
    const result = await checkRateLimit("createOrder", "u1", { db: fakeDb({ fail: true }) });
    assert.equal(result.allowed, true);
  });

  test("an unknown policy is a programming error, not an open door", async () => {
    await assert.rejects(checkRateLimit("nope", "u1", { db: fakeDb() }), /Unknown rate limit policy/);
  });
});
