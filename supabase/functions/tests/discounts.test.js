import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { HttpError } from "../_shared/errors.js";
import {
  DISCOUNT_MESSAGES,
  normalizeDiscountCode,
  discountFromRow,
  isDiscountLive,
  priceDiscount,
  discountTriggerRefusal,
} from "../_shared/discounts.js";

const NOW = Date.parse("2026-10-03T12:00:00Z");
const discount = (overrides = {}) => ({
  id: "d1",
  code: "SAVE10",
  kind: "percentage",
  value: 10,
  minSubtotal: 0,
  productIds: [],
  startsAt: "2026-10-01T00:00:00Z",
  endsAt: null,
  isActive: true,
  ...overrides,
});
const lines = [
  { pid: "a", retailLineTotalUsd: 30 },
  { pid: "b", retailLineTotalUsd: 20 },
];
const refusedWith = (fn, status, pattern) => {
  assert.throws(fn, (err) =>
    err instanceof HttpError && err.status === status && pattern.test(err.message));
};

describe("normalizeDiscountCode", () => {
  test("trims and upper-cases what the buyer typed", () => {
    assert.equal(normalizeDiscountCode("  save10 "), "SAVE10");
  });

  test("treats a missing or blank code as no code", () => {
    assert.equal(normalizeDiscountCode(undefined), null);
    assert.equal(normalizeDiscountCode(null), null);
    assert.equal(normalizeDiscountCode("   "), null);
  });

  test("refuses a code the table could never hold, as an invalid code", () => {
    refusedWith(() => normalizeDiscountCode("a b"), 422, /isn't valid/);
    refusedWith(() => normalizeDiscountCode("AB"), 422, /isn't valid/);
    refusedWith(() => normalizeDiscountCode("X".repeat(33)), 422, /isn't valid/);
  });

  test("refuses a non-text code as a bad request", () => {
    refusedWith(() => normalizeDiscountCode(10), 400, /must be text/);
  });
});

describe("discountFromRow", () => {
  test("reads the snake_case row and coerces Postgres numerics", () => {
    const parsed = discountFromRow({
      id: "d1", code: "SAVE10", kind: "fixed_amount", value: "5.50",
      min_subtotal: "20.00", product_ids: ["a"], starts_at: "2026-10-01T00:00:00Z",
      ends_at: null, is_active: true,
    });
    assert.equal(parsed.value, 5.5);
    assert.equal(parsed.minSubtotal, 20);
    assert.deepEqual(parsed.productIds, ["a"]);
  });

  test("is null for no row", () => {
    assert.equal(discountFromRow(null), null);
  });
});

describe("isDiscountLive", () => {
  test("accepts an active code inside its dates", () => {
    assert.equal(isDiscountLive(discount(), NOW), true);
    assert.equal(isDiscountLive(discount({ endsAt: "2026-10-04T00:00:00Z" }), NOW), true);
  });

  test("refuses a missing, inactive, future or ended code", () => {
    assert.equal(isDiscountLive(null, NOW), false);
    assert.equal(isDiscountLive(discount({ isActive: false }), NOW), false);
    assert.equal(isDiscountLive(discount({ startsAt: "2026-10-04T00:00:00Z" }), NOW), false);
    assert.equal(isDiscountLive(discount({ endsAt: "2026-10-03T12:00:00Z" }), NOW), false);
  });

  test("refuses an unreadable end date rather than treating it as open-ended", () => {
    assert.equal(isDiscountLive(discount({ endsAt: "not a date" }), NOW), false);
  });

  test("refuses an unknown kind or a non-positive value", () => {
    assert.equal(isDiscountLive(discount({ kind: "free_shipping" }), NOW), false);
    assert.equal(isDiscountLive(discount({ value: 0 }), NOW), false);
    assert.equal(isDiscountLive(discount({ value: NaN }), NOW), false);
  });
});

describe("priceDiscount", () => {
  test("takes a percentage off the whole subtotal", () => {
    assert.equal(priceDiscount(discount(), lines), 5);
  });

  test("rounds a percentage to cents", () => {
    assert.equal(priceDiscount(discount({ value: 15 }), [{ pid: "a", retailLineTotalUsd: 19.99 }]), 3);
  });

  test("takes a fixed amount off, never more than the goods cost", () => {
    assert.equal(priceDiscount(discount({ kind: "fixed_amount", value: 7.5 }), lines), 7.5);
    assert.equal(priceDiscount(discount({ kind: "fixed_amount", value: 500 }), lines), 50);
  });

  test("limits a product-specific code to those products' lines", () => {
    assert.equal(priceDiscount(discount({ productIds: ["b"] }), lines), 2);
    assert.equal(
        priceDiscount(discount({ kind: "fixed_amount", value: 25, productIds: ["b"] }), lines), 20);
  });

  test("refuses a cart holding none of the code's products", () => {
    refusedWith(() => priceDiscount(discount({ productIds: ["z"] }), lines), 422, /doesn't apply/);
  });

  test("refuses a cart below the minimum, measured on the whole subtotal", () => {
    refusedWith(() => priceDiscount(discount({ minSubtotal: 50.01 }), lines), 422, /at least USD 50\.01/);
    assert.equal(priceDiscount(discount({ minSubtotal: 50, productIds: ["b"] }), lines), 2);
  });
});

describe("discountTriggerRefusal", () => {
  const dbError = (message) => {
    const err = new Error(`Database error P0001: ${message}`);
    err.cause = { code: "P0001", message };
    return err;
  };

  test("maps each orders_enforce_discount exception to the buyer's message", () => {
    assert.equal(discountTriggerRefusal(dbError("discount_exhausted")), DISCOUNT_MESSAGES.exhausted);
    assert.equal(discountTriggerRefusal(dbError("discount_already_used")), DISCOUNT_MESSAGES.alreadyUsed);
    assert.equal(discountTriggerRefusal(dbError("discount_unavailable")), DISCOUNT_MESSAGES.invalid);
  });

  test("leaves any other database error alone", () => {
    assert.equal(discountTriggerRefusal(dbError("duplicate key")), null);
    assert.equal(discountTriggerRefusal(undefined), null);
  });
});
