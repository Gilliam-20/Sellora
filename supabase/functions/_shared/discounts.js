import { badRequest, unprocessable } from "./errors.js";
import { millisOf } from "./time.js";

// Discount codes (implementation plan PHASE 9). The table, its limits and
// the storefront lookup are in supabase/migrations/20261003000100_discounts.sql;
// this is how createOrder prices one. Pure, so it's tested without a
// database (tests/discounts.test.js).

// Same shape as the discounts.code check constraint.
const CODE_PATTERN = /^[A-Z0-9][A-Z0-9_-]{2,31}$/;

// What the buyer is told. A code that doesn't exist, belongs to another
// store, is switched off or is outside its dates all read the same, so the
// answer doesn't help anyone guess codes.
const DISCOUNT_MESSAGES = Object.freeze({
  invalid: "This discount code isn't valid",
  exhausted: "This discount code has reached its usage limit",
  alreadyUsed: "You've already used this discount code",
  notApplicable: "This discount code doesn't apply to anything in your cart",
  belowCost: "This discount code can't be applied to this order",
});

// The orders_enforce_discount trigger's exceptions, by message.
const TRIGGER_REFUSALS = Object.freeze({
  discount_unavailable: DISCOUNT_MESSAGES.invalid,
  discount_exhausted: DISCOUNT_MESSAGES.exhausted,
  discount_already_used: DISCOUNT_MESSAGES.alreadyUsed,
});

const round2 = (value) => Math.round(value * 100) / 100;

/**
 * @param {*} raw The client's `discountCode`.
 * @return {string|null} The code as stored (trimmed, upper-case), or null
 *   when none was sent.
 */
function normalizeDiscountCode(raw) {
  if (raw == null) return null;
  if (typeof raw !== "string") throw badRequest("discountCode must be text");
  const code = raw.trim().toUpperCase();
  if (!code) return null;
  if (!CODE_PATTERN.test(code)) throw unprocessable(DISCOUNT_MESSAGES.invalid);
  return code;
}

/**
 * @param {object|null} row A `discounts` row (snake_case), or null.
 * @return {object|null} The fields pricing reads, camelCase, numerics coerced.
 */
function discountFromRow(row) {
  if (!row) return null;
  return {
    id: row.id,
    code: row.code,
    kind: row.kind,
    value: Number(row.value),
    minSubtotal: Number(row.min_subtotal ?? 0),
    productIds: Array.isArray(row.product_ids) ? row.product_ids : [],
    startsAt: row.starts_at,
    endsAt: row.ends_at,
    isActive: row.is_active === true,
  };
}

/**
 * @param {object|null} discount From discountFromRow.
 * @param {number=} now Current epoch ms.
 * @return {boolean} Whether the code may be used right now. Usage limits
 *   aren't checked here: the trigger checks them when the order is written,
 *   under a lock.
 */
function isDiscountLive(discount, now = Date.now()) {
  if (!discount || !discount.isActive) return false;
  if (!Number.isFinite(discount.value) || discount.value <= 0) return false;
  if (discount.startsAt && millisOf(discount.startsAt) > now) return false;
  if (discount.endsAt && millisOf(discount.endsAt) <= now) return false;
  return discount.kind === "percentage" || discount.kind === "fixed_amount";
}

/**
 * What a live code takes off these lines, in USD. Throws a 422 when the
 * cart is below the code's minimum or holds none of its products.
 * @param {object} discount From discountFromRow, already isDiscountLive.
 * @param {Array<{pid: string, retailLineTotalUsd: number}>} lines
 * @return {number} The discount, never more than the eligible lines' total.
 */
function priceDiscount(discount, lines) {
  const subtotal = round2(lines.reduce((sum, l) => sum + l.retailLineTotalUsd, 0));
  if (subtotal < discount.minSubtotal) {
    throw unprocessable(
        `This discount code needs an order of at least USD ${discount.minSubtotal.toFixed(2)} ` +
        "before shipping");
  }
  const only = new Set(discount.productIds);
  const eligible = round2(only.size === 0 ? subtotal : lines
      .filter((l) => only.has(l.pid))
      .reduce((sum, l) => sum + l.retailLineTotalUsd, 0));
  if (eligible <= 0) throw unprocessable(DISCOUNT_MESSAGES.notApplicable);
  const amount = discount.kind === "percentage" ?
    round2(eligible * Math.min(discount.value, 100) / 100) :
    round2(discount.value);
  return Math.min(amount, eligible);
}

/**
 * @param {Error} err What the orders insert threw.
 * @return {string|null} The buyer-facing reason, when it was the discount
 *   trigger refusing.
 */
function discountTriggerRefusal(err) {
  const message = `${err?.cause?.message ?? ""} ${err?.message ?? ""}`;
  for (const [key, text] of Object.entries(TRIGGER_REFUSALS)) {
    if (message.includes(key)) return text;
  }
  return null;
}

export {
  DISCOUNT_MESSAGES,
  normalizeDiscountCode,
  discountFromRow,
  isDiscountLive,
  priceDiscount,
  discountTriggerRefusal,
};
