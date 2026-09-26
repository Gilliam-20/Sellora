/**
 * Rate limits: per user for the signed-in endpoints, per client IP for the
 * public ones.
 *
 * Accounts are free, so without a per-user limit one script could spend our
 * CJ quota on freight quotes or (worst) use payOrderMpesa to fire STK
 * payment prompts at someone's phone on a loop. The public catalog routes
 * spend the same single CJ quota with no account at all, so they're keyed
 * on the caller's IP instead (`ip:<address>`).
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
  deleteAccount: { limit: 5, windowMs: 60 * MINUTE },
  // Per IP. Generous, because Kenyan mobile carriers put many shoppers
  // behind one carrier-grade NAT address; still far below what it takes to
  // exhaust the CJ quota.
  publicCatalog: { limit: 300, windowMs: 10 * MINUTE },
  // Per IP. IntaSend's own retries fit easily; a flood of forged payloads
  // doesn't.
  webhook: { limit: 600, windowMs: 10 * MINUTE },
});

/**
 * The address to key a public route's budget on: the first hop of
 * x-forwarded-for, which Supabase's edge sets. Capped in length because it
 * becomes part of a database key.
 * @param {Request} req Incoming request.
 * @return {string} `ip:<address>`, or `ip:unknown`.
 */
function clientKey(req) {
  const forwarded = req.headers.get("x-forwarded-for") || "";
  const address = forwarded.split(",")[0].trim() ||
    req.headers.get("x-real-ip") || "unknown";
  return `ip:${address.slice(0, 64)}`;
}

/**
 * Counts one call against `uid`'s budget for `policyName` (`uid` is the
 * caller's user id, or `clientKey(req)` for a public route).
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

export { POLICIES, checkRateLimit, clientKey };
