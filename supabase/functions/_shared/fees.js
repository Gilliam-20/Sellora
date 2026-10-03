/**
 * Sellora's service fee on a successful sale (TODO.md §15).
 *
 * The rate is an admin setting: the `fees` row of `app_config`, read through
 * the `service_fee_settings()` SQL function, which applies the defaults and
 * bounds (supabase/migrations/20261003000300_orders_import_fees.sql). Every
 * order snapshots the rate and the base it was charged on
 * (`service_fee_rate`, `service_fee_base`), so changing the setting never
 * touches a historical order.
 *
 * By default the fee is charged on the goods only, never shipping or tax.
 * `chargeOnShipping` is the "unless explicitly configured" switch.
 */
import { db, must } from "./db.js";

const DEFAULT_SERVICE_FEE_RATE = 0.07;
// Mirrors the app_config_fees_valid check constraint.
const MAX_SERVICE_FEE_RATE = 0.3;

const DEFAULT_FEE_SETTINGS = Object.freeze({
  serviceFeeRate: DEFAULT_SERVICE_FEE_RATE,
  chargeOnShipping: false,
});

// A setting change reaches checkout within this long on a warm isolate.
const CACHE_MS = 60 * 1000;
let cached = null;
let cachedAt = 0;

/**
 * Coerces a stored `fees` value into usable settings. The database already
 * refuses an out-of-range rate; this is the second copy of that rule, so a
 * bad read can never price an order at a negative or runaway fee.
 * @param {*} value The `service_fee_settings()` result (or raw config).
 * @return {{serviceFeeRate: number, chargeOnShipping: boolean}}
 */
function normalizeFeeSettings(value) {
  const rate = Number(value?.serviceFeeRate);
  return {
    serviceFeeRate: Number.isFinite(rate) && rate >= 0 && rate <= MAX_SERVICE_FEE_RATE ?
      rate : DEFAULT_SERVICE_FEE_RATE,
    chargeOnShipping: value?.chargeOnShipping === true,
  };
}

/**
 * The current fee settings. Throws on a database error rather than
 * guessing: checkout must not snapshot a fee it didn't read.
 * @return {Promise<{serviceFeeRate: number, chargeOnShipping: boolean}>}
 */
async function getFeeSettings() {
  if (cached && Date.now() - cachedAt < CACHE_MS) return cached;
  cached = normalizeFeeSettings(must(await db().rpc("service_fee_settings")));
  cachedAt = Date.now();
  return cached;
}

/** Test hook: forget the cached settings. */
function clearFeeSettingsCache() {
  cached = null;
  cachedAt = 0;
}

export {
  DEFAULT_FEE_SETTINGS,
  DEFAULT_SERVICE_FEE_RATE,
  MAX_SERVICE_FEE_RATE,
  clearFeeSettingsCache,
  getFeeSettings,
  normalizeFeeSettings,
};
