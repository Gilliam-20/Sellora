/**
 * Per-user rate limits for the signed-in endpoints.
 *
 * `maxInstances` caps how much capacity an endpoint can use in total, but
 * not how much of it one caller can take - and accounts are free. Without a
 * per-user limit, one script could hold every checkout instance, spend our
 * CJ quota on freight quotes, or (worst) use payOrderMpesa to fire STK
 * payment prompts at someone's phone on a loop.
 *
 * Counters live in Firestore (`rate_limits/{policy}_{uid}`) rather than in
 * memory, because a warm instance's memory isn't shared with the other
 * instances a burst spins up. The collection has no client rules, so it's
 * Admin-SDK-only. Each doc carries `expireAt`: configure a Firestore TTL
 * policy on `rate_limits.expireAt` so spent windows are deleted for free.
 */
const { db: defaultDb, admin } = require("./firebaseAdmin");
const { logWarning } = require("./logging");

const MINUTE = 60 * 1000;

// Generous for a real shopper, tight for a script. Bucket names are shared
// where two endpoints spend the same thing (both M-Pesa endpoints push a
// prompt to a phone).
const POLICIES = Object.freeze({
  createOrder: { limit: 10, windowMs: 10 * MINUTE },
  calculateFreight: { limit: 30, windowMs: 10 * MINUTE },
  mpesaPush: { limit: 5, windowMs: 10 * MINUTE },
  hostedCheckout: { limit: 10, windowMs: 10 * MINUTE },
  // Clients poll these after paying, so the budget is wider.
  confirmPayment: { limit: 60, windowMs: 10 * MINUTE },
  orderTracking: { limit: 30, windowMs: 10 * MINUTE },
  review: { limit: 20, windowMs: 60 * MINUTE },
  subscribe: { limit: 10, windowMs: 60 * MINUTE },
});

/**
 * Fixed-window counter step. Pure, so the arithmetic is testable without
 * Firestore.
 * @param {{windowStart: number, count: number}|undefined} state Stored state.
 * @param {number} now Epoch ms.
 * @param {{limit: number, windowMs: number}} policy
 * @return {{allowed: boolean, next: object, retryAfterMs: number}}
 */
function consume(state, now, { limit, windowMs }) {
  const current = state && Number.isFinite(state.windowStart) &&
      now - state.windowStart < windowMs ?
    state :
    { windowStart: now, count: 0 };
  if (current.count >= limit) {
    return {
      allowed: false,
      next: current,
      retryAfterMs: current.windowStart + windowMs - now,
    };
  }
  return {
    allowed: true,
    next: { windowStart: current.windowStart, count: current.count + 1 },
    retryAfterMs: 0,
  };
}

/**
 * Counts one call against `uid`'s budget for `policyName`.
 *
 * Fails open: if Firestore itself errors, the call is allowed and the
 * failure logged. A limiter outage shouldn't take checkout down with it, and
 * `maxInstances` still bounds the total.
 * @param {string} policyName Key of POLICIES.
 * @param {string} uid Caller's Firebase Auth uid.
 * @param {object=} deps Injectable for tests.
 * @return {Promise<{allowed: boolean, retryAfterMs: number}>}
 */
async function checkRateLimit(policyName, uid, { db = defaultDb, now = Date.now() } = {}) {
  const policy = POLICIES[policyName];
  if (!policy) throw new Error(`Unknown rate limit policy: ${policyName}`);
  const ref = db.collection("rate_limits").doc(`${policyName}_${uid}`);
  try {
    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const result = consume(snap.exists ? snap.data() : undefined, now, policy);
      if (result.allowed) {
        tx.set(ref, {
          ...result.next,
          expireAt: admin.firestore.Timestamp.fromMillis(
              result.next.windowStart + policy.windowMs),
        });
      }
      return { allowed: result.allowed, retryAfterMs: result.retryAfterMs };
    });
  } catch (err) {
    logWarning("rate_limit_unavailable", { policy: policyName, uid }, err);
    return { allowed: true, retryAfterMs: 0 };
  }
}

module.exports = { POLICIES, consume, checkRateLimit };
