const axios = require("axios");
const { db } = require("./firebaseAdmin");
const { ALERTS, logAlert, logWarning } = require("./logging");

// CJ product prices come back in USD; checkout/pricing across regions needs
// amounts converted to the shopper's local currency. We cache one USD-base
// rate set/day in Firestore so checkout doesn't depend on a live external
// call on every request.
const FX_DOC = db.collection("config").doc("fx");
const CACHE_MS = 24 * 60 * 60 * 1000;

// A rate this old means the daily refresh has been failing for days and
// nobody noticed - worth an alert, but still better than no rate at all.
const STALE_ALERT_MS = 48 * 60 * 60 * 1000;
// Past this, every price quoted from the rate is a guess. KES moved ~14% in
// a year; silently under-charging by that much on every order for weeks is
// worse than a checkout that fails loudly and gets fixed.
const MAX_STALENESS_MS = 14 * 24 * 60 * 60 * 1000;

const QUOTE_CURRENCIES = ["KES", "EUR", "GBP"];

// Last resort: no cached rate has ever been written AND the live fetch is
// failing. These are static and drift with the market, so using them raises
// an alert - the fix is to get the scheduled refresh working, not to lean on
// these numbers.
const FALLBACK_RATES = Object.freeze({ KES: 129, EUR: 0.92, GBP: 0.79 });

/**
 * @return {Promise<Object<string, number>>} USD-base rates for each of
 *   `QUOTE_CURRENCIES`, fetched live from the FX provider.
 */
async function fetchLiveUsdRates() {
  // Free, no API key required. Swap for a paid provider if you need higher
  // reliability/SLA at scale.
  const res = await axios.get(
      "https://open.er-api.com/v6/latest/USD", { timeout: 10000 });
  const rates = {};
  for (const currency of QUOTE_CURRENCIES) {
    const rate = res.data?.rates?.[currency];
    if (!rate) {
      throw new Error(`${currency} rate missing from FX provider response`);
    }
    rates[currency] = rate;
  }
  return rates;
}

/**
 * Pivots a cached USD-base rate document to a `from`->`to` rate, going
 * through the doc's base currency when neither side of the conversion is
 * that base.
 * @param {{base: string, rates: Object<string, number>}} doc Cached rate
 *   doc, e.g. `{ base: "USD", rates: { KES: 129, EUR: 0.92 } }`.
 * @param {string} from Source currency code.
 * @param {string} to Target currency code.
 * @return {number} Multiplier such that `amountIn(from) * rate =
 *   amountIn(to)`.
 */
function pivotRate(doc, from, to) {
  if (from === to) return 1;
  const base = doc.base;
  const rates = doc.rates || {};
  if (from === base) {
    const rate = rates[to];
    if (!rate) throw new Error(`No cached rate for ${base}->${to}`);
    return rate;
  }
  if (to === base) {
    const rate = rates[from];
    if (!rate) throw new Error(`No cached rate for ${from}->${base}`);
    return 1 / rate;
  }
  const fromRate = rates[from];
  const toRate = rates[to];
  if (!fromRate || !toRate) {
    throw new Error(`No cached rate to pivot ${from}->${to} through ${base}`);
  }
  return toRate / fromRate;
}

/**
 * Age of a cached rate doc. Firestore hands `fetchedAt` back as a Timestamp,
 * but `refreshFxRates` returns the doc it just wrote, where it's still a Date.
 * @param {*} fetchedAt The doc's `fetchedAt` field.
 * @param {number=} now Current epoch ms.
 * @return {number} Age in ms, or `Infinity` when there's no usable timestamp.
 */
function rateAgeMs(fetchedAt, now = Date.now()) {
  const millis = fetchedAt?.toMillis?.() ??
      (fetchedAt instanceof Date ? fetchedAt.getTime() : Number(fetchedAt));
  if (!Number.isFinite(millis) || millis <= 0) return Infinity;
  return now - millis;
}

/**
 * How a cached rate of this age may be used.
 * @param {number} ageMs Age from `rateAgeMs`.
 * @return {string} "fresh" (serve as-is), "aging" (serve, refresh due),
 *   "stale" (serve but alert) or "expired" (refuse to price from it).
 */
function rateStaleness(ageMs) {
  if (ageMs >= MAX_STALENESS_MS) return "expired";
  if (ageMs >= STALE_ALERT_MS) return "stale";
  if (ageMs >= CACHE_MS) return "aging";
  return "fresh";
}

/**
 * Returns the cached rate doc, refreshing it if it's more than 24h old.
 *
 * When the refresh fails the cached rate is still served - but only up to
 * `MAX_STALENESS_MS`, past which pricing from it would quietly mis-charge
 * every order, so it throws instead.
 * @return {Promise<object>} The rate doc to price from.
 */
async function getFxDoc() {
  const snap = await FX_DOC.get();
  const cached = snap.exists ? snap.data() : null;
  const age = cached ? rateAgeMs(cached.fetchedAt) : Infinity;
  if (cached && rateStaleness(age) === "fresh") return cached;

  try {
    return await refreshFxRates();
  } catch (err) {
    if (!cached) {
      logAlert(ALERTS.FX_FALLBACK, {
        reason: "no cached rate has ever been written",
        rates: FALLBACK_RATES,
      }, err);
      return { base: "USD", rates: FALLBACK_RATES, fetchedAt: null };
    }

    const ageHours = Math.round(age / (60 * 60 * 1000));
    const staleness = rateStaleness(age);
    if (staleness === "expired") {
      logAlert(ALERTS.FX_STALE, {
        ageHours,
        maxAgeHours: MAX_STALENESS_MS / (60 * 60 * 1000),
        outcome: "refused",
      }, err);
      throw new Error(
          `FX rates are ${ageHours}h old and the refresh is failing; ` +
          "refusing to price an order from them");
    }
    if (staleness === "stale") {
      logAlert(ALERTS.FX_STALE, { ageHours, outcome: "served" }, err);
    } else {
      logWarning("fx_refresh_failed", { ageHours }, err);
    }
    return cached;
  }
}

/** Call this from a daily scheduled function to keep the cache warm. */
async function refreshFxRates() {
  const rates = await fetchLiveUsdRates();
  const doc = { base: "USD", rates, fetchedAt: new Date() };
  await FX_DOC.set(doc);
  return doc;
}

/**
 * @param {string} from Source currency code.
 * @param {string} to Target currency code.
 * @return {Promise<number>} Multiplier to convert an amount in `from` into
 *   `to`, using the cached rate doc and pivoting through USD when neither
 *   side is USD.
 */
async function getRate(from, to) {
  const doc = await getFxDoc();
  return pivotRate(doc, from, to);
}

/** @deprecated use `getRate("USD", "KES")`. Kept for existing callers. */
async function getUsdToKesRate() {
  return getRate("USD", "KES");
}

/** @deprecated use `refreshFxRates`. Kept for existing callers. */
async function refreshUsdToKesRate() {
  const doc = await refreshFxRates();
  return doc.rates.KES;
}

module.exports = {
  getRate,
  refreshFxRates,
  pivotRate,
  rateAgeMs,
  rateStaleness,
  getUsdToKesRate,
  refreshUsdToKesRate,
  STALE_ALERT_MS,
  MAX_STALENESS_MS,
};
