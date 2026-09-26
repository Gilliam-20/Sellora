/**
 * Per-user rate limits for the signed-in endpoints.
 *
 * Accounts are free, so without a per-user limit one script could spend our
 * CJ quota on freight quotes or (worst) use payOrderMpesa to fire STK
 * payment prompts at someone's phone on a loop.
 *
 * Counters live in Postgres (`public.rate_limits`, service role only)
 * rather than in memory, because a warm isolate's memory isn't shared with
 * the others a burst spins up. The fixed-window arithmetic, and the row
 * lock that serializes one user's concurrent calls, are both in the
 * `consume_rate_limit` SQL function (supabase/migrations). Spent windows are
 * deleted hourly by pg_cron.
 */
import { db } from "./db.js";
import { logWarning } from "./logging.js";

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
  subscribe: { limit: 10, windowMs: 60 * MINUTE },
});

/**
 * Counts one call against `uid`'s budget for `policyName`.
 *
 * Fails open: if the database itself errors, the call is allowed and the
 * failure logged. A limiter outage shouldn't take checkout down with it.
 * @param {string} policyName Key of POLICIES.
 * @param {string} uid Caller's user id.
 * @param {object=} deps Injectable for tests.
 * @return {Promise<{allowed: boolean, retryAfterMs: number}>}
 */
async function checkRateLimit(policyName, uid, { client } = {}) {
  const policy = POLICIES[policyName];
  if (!policy) throw new Error(`Unknown rate limit policy: ${policyName}`);
  try {
    const { data, error } = await (client ?? db()).rpc("consume_rate_limit", {
      p_key: `${policyName}:${uid}`,
      p_limit: policy.limit,
      p_window_ms: policy.windowMs,
    });
    if (error) throw new Error(error.message);
    const row = Array.isArray(data) ? data[0] : data;
    return {
      allowed: row?.allowed !== false,
      retryAfterMs: Number(row?.retry_after_ms) || 0,
    };
  } catch (err) {
    logWarning("rate_limit_unavailable", { policy: policyName, uid }, err);
    return { allowed: true, retryAfterMs: 0 };
  }
}

export { POLICIES, checkRateLimit };
