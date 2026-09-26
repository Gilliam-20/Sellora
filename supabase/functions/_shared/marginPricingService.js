/**
 * Profit-margin-based pricing engine.
 *
 * Pure, stateless math - no database/network access - so it can be reused
 * anywhere a selling price needs to be derived from costs (catalog pricing,
 * checkout re-pricing, admin "what-if" tooling) and unit-tested in isolation.
 * The single source of truth for the *default* target margin and the other
 * cost inputs (payment fee %, advertising/refund allowances) is the
 * `app_config` pricing row read by `pricing.js`, which calls
 * into this file.
 *
 * Core formula (net margin is measured against the selling price, and the
 * payment-processing fee is a percentage of the selling price rather than a
 * fixed cost, so it has to live in the denominator, not `fixedCosts`):
 *
 *   fixedCosts   = supplierCost + shippingCost + advertisingCost
 *                  + refundAllowance
 *   sellingPrice = fixedCosts / (1 - targetNetMargin - paymentFeePercentage)
 *
 * Solving `netProfit = sellingPrice - fixedCosts - paymentFeePercentage *
 * sellingPrice` for the price that makes `netProfit == targetNetMargin *
 * sellingPrice` gives exactly the formula above.
 */

const DEFAULT_TARGET_NET_MARGIN = 0.20;
const MINIMUM_ACCEPTABLE_MARGIN = 0.15;
const GROWTH_MARGIN_RANGE = Object.freeze({ min: 0.10, max: 0.15 });
const EXCELLENT_MARGIN_RANGE = Object.freeze({ min: 0.25, max: 0.30 });

// Flagging thresholds. Deliberately simple constants rather than more
// config - they exist to surface a "look at this" signal to an admin, not
// to gate a hard business rule.
const SHIPPING_TO_COST_WARNING_RATIO = 0.75;
const EXCESSIVE_PRICE_MULTIPLIER = 5;

const ZERO_DECIMAL_CURRENCIES = new Set(["KES", "JPY"]);

/**
 * @param {number} value Raw value.
 * @param {number} fallback Fallback for missing/negative/NaN input.
 * @return {number} `value` if it's a finite number >= 0, else `fallback`.
 */
function sanitizeNonNegative(value, fallback = 0) {
  const n = Number(value);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
}

/**
 * @param {number} value Raw value.
 * @param {number} min Lower bound.
 * @param {number} max Upper bound.
 * @return {number} `value` clamped to `[min, max]`.
 */
function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

/**
 * Rounds to cents, purely to keep intermediate money math free of floating
 * point noise (e.g. 0.1 + 0.2). Not the customer-facing rounding step.
 * @param {number} value Raw value.
 * @return {number} Value rounded to 2 decimal places.
 */
function round2(value) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

/**
 * @param {number} increment Rounding increment, e.g. 0.01 or 1.
 * @return {number} Number of decimal places implied by `increment`.
 */
function decimalPlacesOf(increment) {
  const s = String(increment);
  const i = s.indexOf(".");
  return i === -1 ? 0 : s.length - i - 1;
}

/**
 * @param {string=} currency ISO currency code.
 * @return {number} A sensible default rounding increment for that currency.
 */
function defaultIncrementFor(currency) {
  const isZeroDecimal =
      ZERO_DECIMAL_CURRENCIES.has(String(currency || "USD").toUpperCase());
  return isZeroDecimal ? 1 : 0.01;
}

/**
 * Rounds a raw price *up* to the nearest increment. Rounding up (never
 * down) ensures the rounding step can never erode the target margin below
 * what was calculated.
 * @param {number} value Raw selling price.
 * @param {number} increment Rounding increment.
 * @return {number} Customer-facing, non-negative selling price.
 */
function roundForCustomer(value, increment) {
  if (!Number.isFinite(value) || value <= 0) return 0;
  const inc = Number.isFinite(increment) && increment > 0 ? increment : 0.01;
  const rounded = Math.ceil(value / inc) * inc;
  return Number(rounded.toFixed(decimalPlacesOf(inc)));
}

/**
 * Marks a pre-VAT USD selling price up by VAT. Net margin/profit are
 * always measured against the pre-VAT price - VAT is a pass-through tax,
 * not revenue - so this is applied only as a final display step, never fed
 * back into `calculateSellingPrice`'s margin-solving math.
 * @param {number} sellingPriceUsd Pre-VAT selling price, in USD.
 * @param {number} vatRate VAT fraction (e.g. 0.20 for 20%). 0 for regions
 *   with no VAT.
 * @return {number} `sellingPriceUsd` marked up by VAT, still in USD.
 */
function applyVat(sellingPriceUsd, vatRate = 0) {
  const price = sanitizeNonNegative(sellingPriceUsd);
  const rate = clamp(sanitizeNonNegative(vatRate), 0, 1);
  return round2(price * (1 + rate));
}

/**
 * Converts a USD amount into another currency using a pre-resolved
 * exchange rate - e.g. from `fx.js`'s `getRate("USD", currency)` - and
 * rounds it using that currency's own display conventions (whole units for
 * a zero-decimal currency like KES, cents otherwise). This module never
 * calls `fx.js` itself: it stays pure/synchronous, and callers that need a
 * real conversion resolve `fxRate` themselves and pass it in.
 * @param {number} usdAmount Amount in USD.
 * @param {object} opts `{ fxRate, currency }`. `fxRate` defaults to 1
 *   (no-op conversion) when the caller has no real rate to supply.
 * @return {number} The converted, rounded amount in `currency`.
 */
function convertToCurrency(usdAmount, { fxRate = 1, currency = "USD" } = {}) {
  const amount = sanitizeNonNegative(usdAmount);
  const rate = Number.isFinite(fxRate) && fxRate > 0 ? fxRate : 1;
  return roundForCustomer(amount * rate, defaultIncrementFor(currency));
}

/**
 * @param {number} ratio Fraction, e.g. 0.2.
 * @return {string} Human-readable percentage, e.g. "20.0%".
 */
function pct(ratio) {
  return `${(ratio * 100).toFixed(1)}%`;
}

/**
 * @param {string} code Machine-readable flag code.
 * @param {string} severity "error" | "warning".
 * @param {string} message Human-readable explanation.
 * @return {{code: string, severity: string, message: string}} Flag object.
 */
function flag(code, severity, message) {
  return { code, severity, message };
}

/**
 * Solves for the selling price that hits `targetNetMargin` given the cost
 * inputs. This is the "recommended selling price" calculation.
 * @param {object} input Cost/margin inputs.
 * @param {number=} input.supplierCost Product/supplier cost.
 * @param {number=} input.shippingCost Shipping cost.
 * @param {number=} input.paymentFeePercentage Payment fee as a fraction of
 *   price (e.g. 0.03).
 * @param {number=} input.advertisingCost Estimated ad spend allowance.
 * @param {number=} input.refundAllowance Refund/return/operational
 *   allowance.
 * @param {number=} input.targetNetMargin Desired net margin as a fraction
 *   (e.g. 0.20).
 * @param {string=} input.currency ISO currency code, used to pick a
 *   default rounding increment.
 * @param {number=} input.roundingIncrement Explicit rounding increment
 *   override.
 * @return {object} `{ sellingPrice, achievable, fixedCosts, denominator,
 *   currency, roundingIncrement }`.
 */
function calculateSellingPrice({
  supplierCost = 0,
  shippingCost = 0,
  paymentFeePercentage = 0,
  advertisingCost = 0,
  refundAllowance = 0,
  targetNetMargin = DEFAULT_TARGET_NET_MARGIN,
  currency = "USD",
  roundingIncrement,
} = {}) {
  const cost = sanitizeNonNegative(supplierCost);
  const shipping = sanitizeNonNegative(shippingCost);
  const feePct = clamp(sanitizeNonNegative(paymentFeePercentage), 0, 0.99);
  const advertising = sanitizeNonNegative(advertisingCost);
  const refund = sanitizeNonNegative(refundAllowance);
  const margin = clamp(sanitizeNonNegative(targetNetMargin), 0, 0.99);
  const increment = roundingIncrement ?? defaultIncrementFor(currency);

  const fixedCosts = round2(cost + shipping + advertising + refund);
  const denominator = round2(1 - margin - feePct);
  const achievable = denominator > 0;
  // If the target margin can't mathematically be met on top of the payment
  // fee, fall back to a price that at least covers costs + the fee (0% net
  // margin) rather than returning an invalid/negative/infinite price.
  const rawPrice = achievable ?
    fixedCosts / denominator :
    fixedCosts / Math.max(1 - feePct, 0.01);

  return {
    sellingPrice: roundForCustomer(Math.max(rawPrice, 0), increment),
    achievable,
    fixedCosts,
    denominator,
    currency,
    roundingIncrement: increment,
  };
}

/**
 * The selling price at which net profit is exactly zero (recovers all
 * costs and the payment fee, no margin).
 * @param {object} input Cost inputs (no `targetNetMargin` - always 0).
 * @return {object} Same shape as `calculateSellingPrice`'s return value.
 */
function calculateBreakEvenPrice(input = {}) {
  return calculateSellingPrice({ ...input, targetNetMargin: 0 });
}

/**
 * @param {object} input Inputs.
 * @param {number} input.sellingPrice Selling price.
 * @param {number=} input.supplierCost Product/supplier cost.
 * @param {number=} input.shippingCost Shipping cost.
 * @return {number} Selling price minus product and shipping cost only.
 */
function calculateGrossProfit({
  sellingPrice,
  supplierCost = 0,
  shippingCost = 0,
}) {
  return round2(
      sanitizeNonNegative(sellingPrice) -
      sanitizeNonNegative(supplierCost) -
      sanitizeNonNegative(shippingCost),
  );
}

/**
 * @param {object} input Inputs.
 * @param {number} input.sellingPrice Selling price.
 * @param {number=} input.supplierCost Product/supplier cost.
 * @param {number=} input.shippingCost Shipping cost.
 * @param {number=} input.paymentFeePercentage Payment fee as a fraction of
 *   price.
 * @param {number=} input.advertisingCost Advertising allowance.
 * @param {number=} input.refundAllowance Refund/operational allowance.
 * @return {number} Profit after every cost, including the
 *   percentage-based payment fee.
 */
function calculateNetProfit({
  sellingPrice,
  supplierCost = 0,
  shippingCost = 0,
  paymentFeePercentage = 0,
  advertisingCost = 0,
  refundAllowance = 0,
}) {
  const sp = sanitizeNonNegative(sellingPrice);
  const feePct = clamp(sanitizeNonNegative(paymentFeePercentage), 0, 0.99);
  const totalCosts =
      sanitizeNonNegative(supplierCost) +
      sanitizeNonNegative(shippingCost) +
      sanitizeNonNegative(advertisingCost) +
      sanitizeNonNegative(refundAllowance) +
      sp * feePct;
  return round2(sp - totalCosts);
}

/**
 * @param {object} input Inputs.
 * @param {number} input.sellingPrice Selling price.
 * @param {number} input.grossProfit Gross profit (see
 *   `calculateGrossProfit`).
 * @return {number} Gross profit as a fraction of selling price (0 if
 *   price is 0).
 */
function calculateGrossMarginPercent({ sellingPrice, grossProfit }) {
  const sp = sanitizeNonNegative(sellingPrice);
  return sp > 0 ? grossProfit / sp : 0;
}

/**
 * @param {object} input Inputs.
 * @param {number} input.sellingPrice Selling price.
 * @param {number} input.netProfit Net profit (see `calculateNetProfit`).
 * @return {number} Net profit as a fraction of selling price (0 if price
 *   is 0).
 */
function calculateNetMarginPercent({ sellingPrice, netProfit }) {
  const sp = sanitizeNonNegative(sellingPrice);
  return sp > 0 ? netProfit / sp : 0;
}

/**
 * @param {object} input Inputs.
 * @param {number} input.netProfit Per-unit net profit.
 * @param {number=} input.quantity Units in the order (defaults to 1).
 * @return {number} Net profit for the whole order line.
 */
function calculateProfitPerOrder({ netProfit, quantity = 1 }) {
  const qty = Number.isFinite(quantity) && quantity > 0 ? quantity : 1;
  return round2(netProfit * qty);
}

/**
 * The most advertising/customer-acquisition spend this product can absorb
 * at a given selling price while still hitting `targetNetMargin`. Useful
 * for ad bidding: if your actual CPA is below this, the product is still
 * on-target.
 * @param {object} input Inputs.
 * @param {number} input.sellingPrice Selling price the ad budget must
 *   work within.
 * @param {number=} input.supplierCost Product/supplier cost.
 * @param {number=} input.shippingCost Shipping cost.
 * @param {number=} input.paymentFeePercentage Payment fee as a fraction
 *   of price.
 * @param {number=} input.refundAllowance Refund/operational allowance.
 * @param {number=} input.targetNetMargin Desired net margin as a
 *   fraction.
 * @return {number} Non-negative maximum advertising allowance.
 */
function calculateMaxAdvertisingCost({
  sellingPrice,
  supplierCost = 0,
  shippingCost = 0,
  paymentFeePercentage = 0,
  refundAllowance = 0,
  targetNetMargin = DEFAULT_TARGET_NET_MARGIN,
}) {
  const sp = sanitizeNonNegative(sellingPrice);
  const cost = sanitizeNonNegative(supplierCost);
  const shipping = sanitizeNonNegative(shippingCost);
  const feePct = clamp(sanitizeNonNegative(paymentFeePercentage), 0, 0.99);
  const refund = sanitizeNonNegative(refundAllowance);
  const margin = clamp(sanitizeNonNegative(targetNetMargin), 0, 0.99);

  const maxAd = sp * (1 - feePct - margin) - cost - shipping - refund;
  return Math.max(round2(maxAd), 0);
}

/**
 * Re-runs `calculatePricing` with a shallow-merged set of overrides.
 * Exists mainly to document that pricing here is always derived fresh
 * from current costs - there is no cached/stale price to invalidate, so
 * "recalculating" is just calling the same pure function again with new
 * inputs (e.g. after a supplier cost or shipping cost change).
 * @param {object} previousInputs The inputs last used.
 * @param {object} changes Fields to override (e.g. `{ supplierCost: 25
 *   }`).
 * @return {object} A fresh `calculatePricing` result.
 */
function recalculatePricing(previousInputs = {}, changes = {}) {
  return calculatePricing({ ...previousInputs, ...changes });
}

/**
 * The main entry point: computes a recommended selling price (or
 * evaluates a given `sellingPriceOverride`) and every derived profit/
 * margin figure, plus safety flags an admin/product-management surface
 * can use to explain why a product is or isn't profitable.
 * @param {object} input Pricing inputs.
 * @param {number=} input.supplierCost Product/supplier cost.
 * @param {number=} input.shippingCost Shipping cost.
 * @param {number=} input.paymentFeePercentage Payment fee as a fraction
 *   of price (e.g. 0.03 for 3%).
 * @param {number=} input.advertisingCost Estimated advertising/
 *   customer-acquisition allowance.
 * @param {number=} input.refundAllowance Refund/return/operational
 *   allowance.
 * @param {number=} input.targetNetMargin Desired net margin as a
 *   fraction. Defaults to `DEFAULT_TARGET_NET_MARGIN`.
 * @param {string=} input.currency ISO currency code.
 * @param {number=} input.roundingIncrement Explicit rounding increment
 *   override.
 * @param {number=} input.sellingPriceOverride Evaluate this price
 *   instead of solving for one (e.g. to check a competitor-matched
 *   price).
 * @param {number=} input.quantity Units in the order, for
 *   `profitPerOrder`.
 * @param {number=} input.vatRate VAT fraction (e.g. 0.20) applied on top
 *   of the pre-VAT `sellingPrice` for display purposes only - never fed
 *   back into the margin/profit math above. 0 for regions with no VAT.
 * @param {number=} input.fxRate Pre-resolved USD->`localCurrency`
 *   multiplier (e.g. from `fx.js`'s `getRate("USD", localCurrency)`), used
 *   only for the final `localSellingPrice` conversion. Defaults to 1
 *   (no-op) - this module never fetches a rate itself.
 * @param {string=} input.localCurrency Currency `localSellingPrice` is
 *   converted into. Defaults to `currency`.
 * @return {object} Full pricing breakdown - see inline fields.
 */
function calculatePricing(input = {}) {
  const {
    supplierCost = 0,
    shippingCost = 0,
    paymentFeePercentage = 0,
    advertisingCost = 0,
    refundAllowance = 0,
    targetNetMargin = DEFAULT_TARGET_NET_MARGIN,
    currency = "USD",
    roundingIncrement,
    sellingPriceOverride = null,
    quantity = 1,
    vatRate = 0,
    fxRate = 1,
    localCurrency = currency,
  } = input;

  const cost = sanitizeNonNegative(supplierCost);
  const shipping = sanitizeNonNegative(shippingCost);
  const feePct = clamp(sanitizeNonNegative(paymentFeePercentage), 0, 0.99);
  const advertising = sanitizeNonNegative(advertisingCost);
  const refund = sanitizeNonNegative(refundAllowance);
  const margin = clamp(sanitizeNonNegative(targetNetMargin), 0, 0.99);
  const increment = roundingIncrement ?? defaultIncrementFor(currency);
  const qty = Number.isFinite(quantity) && quantity > 0 ? quantity : 1;

  const recommended = calculateSellingPrice({
    supplierCost: cost,
    shippingCost: shipping,
    paymentFeePercentage: feePct,
    advertisingCost: advertising,
    refundAllowance: refund,
    targetNetMargin: margin,
    currency,
    roundingIncrement: increment,
  });

  const sellingPrice = sellingPriceOverride != null ?
    roundForCustomer(sanitizeNonNegative(sellingPriceOverride), increment) :
    recommended.sellingPrice;

  const grossProfit = calculateGrossProfit({
    sellingPrice,
    supplierCost: cost,
    shippingCost: shipping,
  });
  const netProfit = calculateNetProfit({
    sellingPrice,
    supplierCost: cost,
    shippingCost: shipping,
    paymentFeePercentage: feePct,
    advertisingCost: advertising,
    refundAllowance: refund,
  });
  const grossMarginPercent =
      calculateGrossMarginPercent({ sellingPrice, grossProfit });
  const netMarginPercent =
      calculateNetMarginPercent({ sellingPrice, netProfit });
  const profitPerOrder =
      calculateProfitPerOrder({ netProfit, quantity: qty });
  const paymentFeeAmount = round2(sellingPrice * feePct);

  const breakEven = calculateBreakEvenPrice({
    supplierCost: cost,
    shippingCost: shipping,
    paymentFeePercentage: feePct,
    advertisingCost: advertising,
    refundAllowance: refund,
    currency,
    roundingIncrement: increment,
  });

  const maxAdvertisingCost = calculateMaxAdvertisingCost({
    sellingPrice,
    supplierCost: cost,
    shippingCost: shipping,
    paymentFeePercentage: feePct,
    refundAllowance: refund,
    targetNetMargin: margin,
  });

  const flags = [];
  if (!recommended.achievable) {
    flags.push(flag(
        "TARGET_MARGIN_UNREACHABLE",
        "error",
        `A target net margin of ${pct(margin)} plus a ${pct(feePct)} ` +
        "payment fee exceed 100% of the selling price, so the target " +
        "can't be solved for. Falling back to a fee-covering, 0% net " +
        "margin price.",
    ));
  }
  if (netProfit < 0) {
    flags.push(flag(
        "NEGATIVE_PROFIT",
        "error",
        `Selling price ${sellingPrice} ${currency} results in a net ` +
        `loss of ${Math.abs(netProfit)} ${currency}.`,
    ));
  } else if (netMarginPercent < MINIMUM_ACCEPTABLE_MARGIN) {
    flags.push(flag(
        "BELOW_MINIMUM_MARGIN",
        "warning",
        `Net margin ${pct(netMarginPercent)} is below the minimum ` +
        `acceptable target of ${pct(MINIMUM_ACCEPTABLE_MARGIN)}.`,
    ));
  }
  if (cost > 0 && shipping > cost * SHIPPING_TO_COST_WARNING_RATIO) {
    const ratioPct = Math.round(SHIPPING_TO_COST_WARNING_RATIO * 100);
    flags.push(flag(
        "SHIPPING_COST_TOO_HIGH",
        "warning",
        `Shipping cost (${shipping}) is more than ${ratioPct}% of the ` +
        `product cost (${cost}); consider a cheaper logistics option ` +
        "or excluding this product.",
    ));
  }
  if (cost > 0 && sellingPrice > cost * EXCESSIVE_PRICE_MULTIPLIER) {
    flags.push(flag(
        "SELLING_PRICE_EXCESSIVE",
        "warning",
        `Selling price (${sellingPrice}) is more than ` +
        `${EXCESSIVE_PRICE_MULTIPLIER}x the supplier cost (${cost}) ` +
        "and may be uncompetitive.",
    ));
  }
  if (advertising > 0 && advertising > maxAdvertisingCost) {
    flags.push(flag(
        "ADVERTISING_UNPROFITABLE",
        "warning",
        `Advertising allowance (${advertising}) exceeds the maximum ` +
        `(${maxAdvertisingCost}) the target margin can absorb at this ` +
        "price.",
    ));
  }

  // VAT and currency conversion are display-only steps layered on top of
  // the pre-VAT, USD `sellingPrice` computed above - net margin/profit and
  // every flag are measured against that pre-VAT price, unchanged.
  const vat = clamp(sanitizeNonNegative(vatRate), 0, 1);
  const sellingPriceInclVatUsd = applyVat(sellingPrice, vat);
  const vatAmountUsd = round2(sellingPriceInclVatUsd - sellingPrice);
  const localSellingPrice = convertToCurrency(
      sellingPriceInclVatUsd, { fxRate, currency: localCurrency });

  return {
    currency,
    inputs: {
      supplierCost: cost,
      shippingCost: shipping,
      paymentFeePercentage: feePct,
      advertisingCost: advertising,
      refundAllowance: refund,
      targetNetMargin: margin,
      quantity: qty,
      vatRate: vat,
    },
    fixedCosts: recommended.fixedCosts,
    recommendedSellingPrice: recommended.sellingPrice,
    sellingPrice,
    paymentFeeAmount,
    grossProfit,
    netProfit,
    grossMarginPercent,
    netMarginPercent,
    profitPerOrder,
    breakEvenPrice: breakEven.sellingPrice,
    maxAdvertisingCost,
    isMarginAchievable: recommended.achievable,
    isProfitable: netProfit >= 0,
    meetsTargetMargin: netMarginPercent >= margin - 1e-9,
    vatRate: vat,
    vatAmountUsd,
    sellingPriceInclVatUsd,
    fxRate,
    localCurrency,
    localSellingPrice,
    flags,
  };
}

export {
  DEFAULT_TARGET_NET_MARGIN,
  MINIMUM_ACCEPTABLE_MARGIN,
  GROWTH_MARGIN_RANGE,
  EXCELLENT_MARGIN_RANGE,
  calculateSellingPrice,
  calculateBreakEvenPrice,
  calculateGrossProfit,
  calculateNetProfit,
  calculateGrossMarginPercent,
  calculateNetMarginPercent,
  calculateProfitPerOrder,
  calculateMaxAdvertisingCost,
  applyVat,
  convertToCurrency,
  calculatePricing,
  recalculatePricing,
};
