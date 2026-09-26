import { request } from "./http.js";
import { db, must } from "./db.js";
import { requireEnv } from "./env.js";
import { logWarning } from "./logging.js";

// Set this secret once with:
//   npx supabase secrets set CJ_API_KEY=...
// The value is the API Key you generate in CJ personal center > API tab > Add API.
// (This replaced the older email+password login flow.)
const CJ_API_KEY = "CJ_API_KEY";

const CJ_BASE_URL = "https://developers.cjdropshipping.com/api2.0/v1";

// Single cached token row (public.cj_auth_tokens, service role only) shared
// by every invocation/isolate. CJ caches tokens server-side for 24h anyway,
// and access tokens last 15 days, so caching keeps us far under CJ's 1
// request/second auth limit.
const TOKEN_ID = "current";

// Refresh this long before actual expiry to leave comfortable safety margin.
const REFRESH_MARGIN_MS = 24 * 60 * 60 * 1000; // 1 day

// Access tokens last 15 days, so re-reading the token row on every single CJ
// call is pure latency - checkout makes one call per cart line plus freight.
// Memoized per warm isolate, bounded so a token rotated elsewhere is still
// picked up quickly.
const MEMO_TTL_MS = 30 * 60 * 1000; // 30m
let memo = null; // { accessToken, validUntil }
let inFlight = null; // dedupes the concurrent lookups createOrder fans out

async function requestNewToken(apiKey) {
  const res = await request({
    method: "POST",
    url: `${CJ_BASE_URL}/authentication/getAccessToken`,
    data: { apiKey },
  });

  if (!res.data || res.data.code !== 200 || !res.data.result) {
    throw new Error(`CJ getAccessToken failed: ${res.data && res.data.message}`);
  }
  return res.data.data; // { accessToken, accessTokenExpiryDate, refreshToken, refreshTokenExpiryDate, ... }
}

async function requestRefreshedToken(refreshToken) {
  const res = await request({
    method: "POST",
    url: `${CJ_BASE_URL}/authentication/refreshAccessToken`,
    data: { refreshToken },
  });

  if (!res.data || res.data.code !== 200 || !res.data.result) {
    throw new Error(`CJ refreshAccessToken failed: ${res.data && res.data.message}`);
  }
  return res.data.data;
}

/**
 * How long a token may be served from the in-instance memo: the shorter of
 * the memo TTL and the token's own remaining life less the refresh margin, so
 * the memo can never hand out a token the stored path would have refreshed.
 * @param {*} accessTokenExpiryDate CJ's expiry, as stored on the token row.
 * @param {number=} now Current epoch ms.
 * @return {number} Epoch ms until which the memo may be used.
 */
function memoValidUntil(accessTokenExpiryDate, now = Date.now()) {
  const ceiling = now + MEMO_TTL_MS;
  const expiry = new Date(accessTokenExpiryDate ?? "").getTime();
  if (!Number.isFinite(expiry)) return ceiling;
  return Math.min(ceiling, expiry - REFRESH_MARGIN_MS);
}

/**
 * Returns a valid CJ-Access-Token, transparently fetching or refreshing it
 * (and persisting the result in cj_auth_tokens) whenever necessary.
 * @return {Promise<string>} A usable CJ access token.
 */
async function getValidAccessToken() {
  if (memo && memo.validUntil > Date.now()) return memo.accessToken;
  // A cold isolate handling a checkout fires this from every cart line at
  // once; without the shared promise each one does its own database read.
  if (!inFlight) {
    inFlight = loadAccessToken().finally(() => {
      inFlight = null;
    });
  }
  return inFlight;
}

/** Clears the per-instance token memo. For tests. */
function resetAccessTokenMemo() {
  memo = null;
  inFlight = null;
}

/**
 * @param {object} token CJ's token payload.
 * @return {Promise<void>} Resolves once the shared row holds it.
 */
async function storeToken(token) {
  must(await db().from("cj_auth_tokens").upsert({
    id: TOKEN_ID,
    access_token: token.accessToken,
    access_token_expiry_date: token.accessTokenExpiryDate ?? null,
    refresh_token: token.refreshToken ?? null,
    refresh_token_expiry_date: token.refreshTokenExpiryDate ?? null,
    updated_at: new Date().toISOString(),
  }));
}

/**
 * The uncached path: reads the shared token row, refreshing or re-minting
 * the token as needed, and memoizes whatever it ends up using.
 * @return {Promise<string>} A usable CJ access token.
 */
async function loadAccessToken() {
  const row = must(await db().from("cj_auth_tokens")
      .select("*").eq("id", TOKEN_ID).maybeSingle());

  if (row) {
    const data = {
      accessToken: row.access_token,
      accessTokenExpiryDate: row.access_token_expiry_date,
      refreshToken: row.refresh_token,
    };
    const accessExpiry = new Date(data.accessTokenExpiryDate).getTime();

    if (accessExpiry - Date.now() > REFRESH_MARGIN_MS) {
      return memoize(data.accessToken, data.accessTokenExpiryDate);
    }

    // Access token is close to expiry (or expired) - try to refresh it.
    try {
      const refreshed = await requestRefreshedToken(data.refreshToken);
      // CJ's refresh response may omit the refresh token itself; keep ours.
      await storeToken({ refreshToken: data.refreshToken, ...refreshed });
      return memoize(refreshed.accessToken, refreshed.accessTokenExpiryDate);
    } catch (err) {
      logWarning("cj_token_refresh_failed", {}, err);
    }
  }

  const fresh = await requestNewToken(requireEnv(CJ_API_KEY));
  await storeToken(fresh);
  return memoize(fresh.accessToken, fresh.accessTokenExpiryDate);
}

/**
 * @param {string} accessToken Token to serve from memory.
 * @param {*} accessTokenExpiryDate CJ's expiry for it.
 * @return {string} `accessToken`, for chaining.
 */
function memoize(accessToken, accessTokenExpiryDate) {
  memo = { accessToken, validUntil: memoValidUntil(accessTokenExpiryDate) };
  return accessToken;
}

export {
  getValidAccessToken,
  memoValidUntil,
  resetAccessTokenMemo,
  CJ_API_KEY,
  CJ_BASE_URL,
  MEMO_TTL_MS,
  REFRESH_MARGIN_MS,
};
