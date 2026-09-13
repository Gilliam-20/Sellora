const axios = require("axios");
const { defineSecret } = require("firebase-functions/params");
const { db } = require("./firebaseAdmin");
const { logWarning } = require("./logging");

// Set this secret once with:
//   firebase functions:secrets:set CJ_API_KEY
// The value is the API Key you generate in CJ personal center > API tab > Add API.
// (This replaced the older email+password login flow.)
const CJ_API_KEY = defineSecret("CJ_API_KEY");

const CJ_BASE_URL = "https://developers.cjdropshipping.com/api2.0/v1";

// Single cached token doc shared by every function invocation/instance.
// CJ caches tokens server-side for 24h anyway, and access tokens last 15 days,
// so Firestore caching keeps us far under CJ's 1 request/second auth limit.
const TOKEN_DOC = db.collection("cj_config").doc("auth_token");

// Refresh this long before actual expiry to leave comfortable safety margin.
const REFRESH_MARGIN_MS = 24 * 60 * 60 * 1000; // 1 day

// Access tokens last 15 days, so re-reading the Firestore token doc on every
// single CJ call is pure latency - checkout makes one call per cart line plus
// freight, and paid every read. Memoized per warm instance, bounded so a token
// rotated elsewhere is still picked up quickly.
const MEMO_TTL_MS = 30 * 60 * 1000; // 30m
let memo = null; // { accessToken, validUntil }
let inFlight = null; // dedupes the concurrent lookups createOrder fans out

async function requestNewToken(apiKey) {
  const res = await axios.post(
      `${CJ_BASE_URL}/authentication/getAccessToken`,
      { apiKey },
      { headers: { "Content-Type": "application/json" } },
  );

  if (!res.data || res.data.code !== 200 || !res.data.result) {
    throw new Error(`CJ getAccessToken failed: ${res.data && res.data.message}`);
  }
  return res.data.data; // { accessToken, accessTokenExpiryDate, refreshToken, refreshTokenExpiryDate, ... }
}

async function requestRefreshedToken(refreshToken) {
  const res = await axios.post(
      `${CJ_BASE_URL}/authentication/refreshAccessToken`,
      { refreshToken },
      { headers: { "Content-Type": "application/json" } },
  );

  if (!res.data || res.data.code !== 200 || !res.data.result) {
    throw new Error(`CJ refreshAccessToken failed: ${res.data && res.data.message}`);
  }
  return res.data.data;
}

/**
 * How long a token may be served from the in-instance memo: the shorter of
 * the memo TTL and the token's own remaining life less the refresh margin, so
 * the memo can never hand out a token the Firestore path would have refreshed.
 * @param {*} accessTokenExpiryDate CJ's expiry, as stored on the token doc.
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
 * (and persisting the result in Firestore) whenever necessary.
 * @return {Promise<string>} A usable CJ access token.
 */
async function getValidAccessToken() {
  if (memo && memo.validUntil > Date.now()) return memo.accessToken;
  // A cold instance handling a checkout fires this from every cart line at
  // once; without the shared promise each one does its own Firestore read.
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
 * The uncached path: reads the shared token doc, refreshing or re-minting the
 * token as needed, and memoizes whatever it ends up using.
 * @return {Promise<string>} A usable CJ access token.
 */
async function loadAccessToken() {
  const snap = await TOKEN_DOC.get();

  if (snap.exists) {
    const data = snap.data();
    const accessExpiry = new Date(data.accessTokenExpiryDate).getTime();

    if (accessExpiry - Date.now() > REFRESH_MARGIN_MS) {
      return memoize(data.accessToken, data.accessTokenExpiryDate);
    }

    // Access token is close to expiry (or expired) - try to refresh it.
    try {
      const refreshed = await requestRefreshedToken(data.refreshToken);
      await TOKEN_DOC.set(refreshed, { merge: true });
      return memoize(refreshed.accessToken, refreshed.accessTokenExpiryDate);
    } catch (err) {
      logWarning("cj_token_refresh_failed", {}, err);
    }
  }

  const fresh = await requestNewToken(CJ_API_KEY.value());
  await TOKEN_DOC.set(fresh);
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

module.exports = {
  getValidAccessToken,
  memoValidUntil,
  resetAccessTokenMemo,
  CJ_API_KEY,
  CJ_BASE_URL,
  MEMO_TTL_MS,
  REFRESH_MARGIN_MS,
};
