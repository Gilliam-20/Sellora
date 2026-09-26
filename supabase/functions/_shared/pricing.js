import { db, must } from "./db.js";
import * as margin from "./marginPricingService.js";
import { REGION_CONFIG } from "./regions.js";

const CACHE_MS = 5 * 60 * 1000;
let cachedPricing;
let cachedAt = 0;

// Region keys an `app_config` pricing `regionOverrides` entry may be filed under -
// sourced from regions.js so the two stay in sync.
const VALID_REGION_KEYS = Object.freeze(
    [...new Set(Object.values(REGION_CONFIG).map((r) => r.region))],
);

// VAT only applies in these regions - a `vatRate` on any other region's
// override is ignored rather than silently charged.
const VAT_ELIGIBLE_REGIONS = Object.freeze(["eu", "uk"]);

// The 20% target lives here, and only here - change it in the database
// (app_config, key 'pricing') or in these defaults, never inline elsewhere.
const defaults = Object.freeze({
  targetNetMargin: margin.DEFAULT_TARGET_NET_MARGIN, // 0.20
  // Margin recovered on the shipping line itself, kept lower than the
  // product's target margin since shipping isn't the profit driver.
  shippingTargetNetMargin: 0.10,
  // Blended estimate of IntaSend (M-Pesa/card/Google Pay) + PayPal
  // processing fees. Per-provider precision is out of scope here; this is
  // a single estimate used to size the selling price.
  paymentFeePercentage: 0.035,
  advertisingCostUsd: 0,
  refundAllowanceUsd: 0,
  roundingIncrementUsd: 0.01,
  targetNetMarginByCategory: {},
  targetNetMarginByProduct: {},
  regionOverrides: {},
});

/**
 * @param {*} value Raw value.
 * @param {number} fallback Fallback for missing/negative/NaN input.
 * @return {number} `value` if finite and >= 0, else `fallback`.
 */
function positiveNumber(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? number : fallback;
}

/**
 * A margin is a fraction in [0, 1) - reject anything outside that range
 * rather than silently clamping a config typo.
 * @param {*} value Raw value.
 * @param {number} fallback Fallback for an out-of-range value.
 * @return {number} A valid margin fraction.
 */
function marginFraction(value, fallback) {
  const number = Number(value);
  const inRange = Number.isFinite(number) && number >= 0 && number < 1;
  return inRange ? number : fallback;
}

/**
 * @param {*} value Raw `{ [id]: margin }` map from the stored config.
 * @return {object} The same map with only valid margin fractions kept.
 */
function marginOverrideMap(value) {
  if (!value || typeof value !== "object") return {};
  const result = {};
  for (const [key, raw] of Object.entries(value)) {
    const number = Number(raw);
    if (Number.isFinite(number) && number >= 0 && number < 1) {
      result[key] = number;
    }
  }
  return result;
}

/**
 * @param {*} value Raw `regionOverrides` map from the stored pricing
 *   config, e.g. `{ eu: { targetNetMargin: 0.25, paymentFeePercentage:
 *   0.03, vatRate: 0.20 }, kenya: { ... } }`.
 * @return {object} The same map, keyed by the region keys in
 *   `VALID_REGION_KEYS`, with only valid fields kept (`vatRate` dropped
 *   for any region outside `VAT_ELIGIBLE_REGIONS`).
 */
function regionOverrideConfig(value) {
  if (!value || typeof value !== "object") return {};
  const result = {};
  for (const regionKey of VALID_REGION_KEYS) {
    const raw = value[regionKey];
    if (!raw || typeof raw !== "object") continue;
    const override = {};
    if (raw.targetNetMargin !== undefined) {
      const m = marginFraction(raw.targetNetMargin, undefined);
      if (m !== undefined) override.targetNetMargin = m;
    }
    if (raw.paymentFeePercentage !== undefined) {
      const f = marginFraction(raw.paymentFeePercentage, undefined);
      if (f !== undefined) override.paymentFeePercentage = f;
    }
    if (VAT_ELIGIBLE_REGIONS.includes(regionKey) && raw.vatRate !== undefined) {
      const v = marginFraction(raw.vatRate, undefined);
      if (v !== undefined) override.vatRate = v;
    }
    if (Object.keys(override).length > 0) result[regionKey] = override;
  }
  return result;
}

/**
 * Resolves the payment fee % and VAT rate to use for a region, falling
 * back to the store-wide default fee and 0% VAT when there's no override.
 * @param {object} pricing Config from `getPricing()`.
 * @param {string=} regionKey One of `VALID_REGION_KEYS`.
 * @return {{paymentFeePercentage: number, vatRate: number}} Resolved
 *   region pricing inputs.
 */
function resolveRegionPricingInputs(pricing, regionKey) {
  const override = pricing.regionOverrides[regionKey] || {};
  return {
    paymentFeePercentage:
        override.paymentFeePercentage ?? pricing.paymentFeePercentage,
    vatRate: override.vatRate ?? 0,
  };
}

/**
 * Loads the central pricing config (`app_config` row 'pricing'),
 * cached for `CACHE_MS`, falling back to `defaults` for anything missing.
 * @return {Promise<object>} The resolved pricing config.
 */
async function getPricing() {
  if (cachedPricing && Date.now() - cachedAt < CACHE_MS) return cachedPricing;
  const row = must(await db().from("app_config")
      .select("value").eq("key", "pricing").maybeSingle());
  const source = row?.value || {};
  cachedPricing = {
    targetNetMargin: marginFraction(
        source.targetNetMargin, defaults.targetNetMargin),
    shippingTargetNetMargin: marginFraction(
        source.shippingTargetNetMargin, defaults.shippingTargetNetMargin),
    paymentFeePercentage: marginFraction(
        source.paymentFeePercentage, defaults.paymentFeePercentage),
    advertisingCostUsd: positiveNumber(
        source.advertisingCostUsd, defaults.advertisingCostUsd),
    refundAllowanceUsd: positiveNumber(
        source.refundAllowanceUsd, defaults.refundAllowanceUsd),
    roundingIncrementUsd: positiveNumber(
        source.roundingIncrementUsd, defaults.roundingIncrementUsd) ||
        defaults.roundingIncrementUsd,
    targetNetMarginByCategory: marginOverrideMap(
        source.targetNetMarginByCategory),
    targetNetMarginByProduct: marginOverrideMap(
        source.targetNetMarginByProduct),
    regionOverrides: regionOverrideConfig(source.regionOverrides),
  };
  cachedAt = Date.now();
  return cachedPricing;
}

/**
 * Resolves the target net margin for a product: a per-product override
 * wins, then a per-category override, then a per-region override, then
 * the store-wide default.
 * @param {object} pricing Config from `getPricing()`.
 * @param {object} ids `{ pid, categoryId, regionKey }`, all optional.
 * @return {number} The target net margin fraction to use.
 */
function resolveTargetMargin(pricing, { pid, categoryId, regionKey } = {}) {
  if (pid && pricing.targetNetMarginByProduct[pid] !== undefined) {
    return pricing.targetNetMarginByProduct[pid];
  }
  const categoryOverride = pricing.targetNetMarginByCategory[categoryId];
  if (categoryId && categoryOverride !== undefined) {
    return categoryOverride;
  }
  const regionOverride = pricing.regionOverrides[regionKey];
  if (regionKey && regionOverride?.targetNetMargin !== undefined) {
    return regionOverride.targetNetMargin;
  }
  return pricing.targetNetMargin;
}

/**
 * Full profit-margin breakdown for a product's supplier cost: recommended
 * price, expected profit/margin, break-even price, safety flags, VAT and
 * localized price, etc. Use this (rather than `retailProductPrice`)
 * wherever the extra detail is useful, e.g. region-aware checkout/display
 * or future admin/product-management tooling.
 *
 * `categoryId` is only available at browse time (CJ's search/detail
 * responses carry it); order creation only has `pid`, so a category-level
 * override configured in the pricing config affects the catalog price but not
 * the checkout re-price in that edge case. Use a per-product override if a
 * price needs to be guaranteed identical everywhere.
 *
 * `currency`/`fxRate` only affect the result's `localSellingPrice` (and
 * VAT-inclusive USD figure) - the core `sellingPrice` stays in USD,
 * computed the same way regardless of region. `fxRate` must be resolved by
 * the caller (e.g. via `fx.js`'s `getRate("USD", currency)`) since this
 * module stays synchronous and never touches the database/network itself for
 * currency conversion; omit it (default 1) when only the USD price is
 * needed, as order creation does.
 * @param {number} supplierCostUsd Supplier/product cost in USD.
 * @param {object} pricing Config from `getPricing()`.
 * @param {object} opts `{ pid, categoryId, regionKey, shippingCost,
 *   currency, fxRate }`.
 * @return {object} The full `calculatePricing()` breakdown.
 */
function calculateProductPricing(supplierCostUsd, pricing, opts = {}) {
  const {
    pid, categoryId, regionKey, shippingCost = 0, currency = "USD",
    fxRate = 1,
  } = opts;
  const { paymentFeePercentage, vatRate } =
      resolveRegionPricingInputs(pricing, regionKey);
  const targetNetMargin =
      resolveTargetMargin(pricing, { pid, categoryId, regionKey });
  return margin.calculatePricing({
    supplierCost: supplierCostUsd,
    shippingCost,
    paymentFeePercentage,
    advertisingCost: pricing.advertisingCostUsd,
    refundAllowance: pricing.refundAllowanceUsd,
    targetNetMargin,
    currency,
    roundingIncrement: pricing.roundingIncrementUsd,
    vatRate,
    fxRate,
    localCurrency: currency,
  });
}

/**
 * @param {number} supplierCostUsd Supplier/product cost in USD.
 * @param {object} pricing Config from `getPricing()`.
 * @param {object} opts `{ pid, categoryId, regionKey, currency, fxRate }`,
 *   all optional. See `calculateProductPricing` for what `currency`/
 *   `fxRate` do and don't affect.
 * @return {number} The recommended retail price in USD (pre-VAT,
 *   pre-conversion - use `calculateProductPricing` for the localized/VAT-
 *   inclusive price).
 */
function retailProductPrice(supplierCostUsd, pricing, opts = {}) {
  const { pid, categoryId, regionKey, currency, fxRate } = opts;
  const result = calculateProductPricing(supplierCostUsd, pricing, {
    pid, categoryId, regionKey, currency, fxRate,
  });
  if (result.flags.length) {
    const codes = result.flags.map((f) => f.code).join(", ");
    console.warn(`[pricing] product ${pid || "unknown"} flags:`, codes);
  }
  return result.sellingPrice;
}

/**
 * @param {number} supplierShippingUsd Supplier shipping cost in USD.
 * @param {object} pricing Config from `getPricing()`.
 * @param {object} opts `{ regionKey, currency, fxRate }`, all optional.
 *   Shipping has no per-product/category margin tier, so `pid`/
 *   `categoryId` aren't accepted here - only the region affects the fee/
 *   VAT inputs. See `calculateProductPricing` for what `currency`/`fxRate`
 *   do and don't affect.
 * @return {number} The recommended retail shipping price in USD (pre-VAT,
 *   pre-conversion).
 */
function retailShippingPrice(supplierShippingUsd, pricing, opts = {}) {
  const { regionKey, currency = "USD", fxRate = 1 } = opts;
  const { paymentFeePercentage, vatRate } =
      resolveRegionPricingInputs(pricing, regionKey);
  return margin.calculatePricing({
    supplierCost: 0,
    shippingCost: supplierShippingUsd,
    paymentFeePercentage,
    targetNetMargin: pricing.shippingTargetNetMargin,
    roundingIncrement: pricing.roundingIncrementUsd,
    vatRate,
    currency,
    fxRate,
    localCurrency: currency,
  }).sellingPrice;
}

export {
  getPricing,
  resolveTargetMargin,
  calculateProductPricing,
  retailProductPrice,
  retailShippingPrice,
};
