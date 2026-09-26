import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  decidePushClaim,
  paymentRefMatches,
  hasPendingAttempt,
  MAX_FULFILLMENT_ATTEMPTS,
  PUSH_CLAIM_STALE_MS,
  DUPLICATE_ATTEMPT_WINDOW_MS,
  SERVICE_FEE_RATE,
  ORDER_TTL_MS,
  splitServiceFee,
  lineRefusal,
  isExpired,
  validateOrderRequest,
} from "../_shared/orders.js";

// Postgres hands timestamps back as ISO strings, which is what the state
// machine reads.
const timestamp = (millis) => new Date(millis).toISOString();
const NOW = 1_700_000_000_000;

describe("decidePushClaim", () => {
  test("claims an order that has never been pushed", () => {
    assert.deepEqual(decidePushClaim({ cjOrderStatus: "NOT_PUSHED" }, NOW), {
      proceed: true,
      reason: "claimed",
      fulfilled: false,
      attempts: 1,
    });
  });

  test("re-drives a FAILED order, counting the attempt", () => {
    const claim = decidePushClaim(
        { cjOrderStatus: "FAILED", cjPushAttempts: 2 }, NOW);
    assert.equal(claim.proceed, true);
    assert.equal(claim.attempts, 3);
  });

  test("treats PUSHED as terminal and already fulfilled", () => {
    const claim = decidePushClaim({ cjOrderStatus: "PUSHED" }, NOW);
    assert.equal(claim.proceed, false);
    assert.equal(claim.reason, "already_pushed");
    assert.equal(claim.fulfilled, true);
  });

  test("treats NEEDS_RECONCILIATION as terminal and not fulfilled", () => {
    const claim = decidePushClaim(
        { cjOrderStatus: "NEEDS_RECONCILIATION" }, NOW);
    assert.equal(claim.proceed, false);
    assert.equal(claim.reason, "needs_reconciliation");
    assert.equal(claim.fulfilled, false);
  });

  test("refuses a live PUSHING claim - the loser of a webhook/poll race must not double-push", () => {
    const claim = decidePushClaim({
      cjOrderStatus: "PUSHING",
      cjPushClaimedAt: timestamp(NOW - 1000),
    }, NOW);
    assert.equal(claim.proceed, false);
    assert.equal(claim.reason, "push_in_progress");
  });

  test("reclaims a PUSHING claim once it's stale - its holder timed out mid-push", () => {
    const claim = decidePushClaim({
      cjOrderStatus: "PUSHING",
      cjPushClaimedAt: timestamp(NOW - PUSH_CLAIM_STALE_MS - 1),
      cjPushAttempts: 1,
    }, NOW);
    assert.equal(claim.proceed, true);
    assert.equal(claim.attempts, 2);
  });

  test("reclaims a PUSHING order that carries no claim timestamp at all", () => {
    assert.equal(
        decidePushClaim({ cjOrderStatus: "PUSHING" }, NOW).proceed, true);
  });

  test("uses the last attempt of the budget rather than parking early", () => {
    const claim = decidePushClaim({
      cjOrderStatus: "FAILED",
      cjPushAttempts: MAX_FULFILLMENT_ATTEMPTS - 1,
    }, NOW);
    assert.equal(claim.proceed, true);
    assert.equal(claim.attempts, MAX_FULFILLMENT_ATTEMPTS);
  });

  test("parks for a human once the attempt budget is spent", () => {
    const claim = decidePushClaim({
      cjOrderStatus: "FAILED",
      cjPushAttempts: MAX_FULFILLMENT_ATTEMPTS,
    }, NOW);
    assert.equal(claim.proceed, false);
    assert.equal(claim.park, true);
    assert.equal(claim.reason, "attempts_exhausted");
    assert.equal(claim.fulfilled, false);
  });
});

describe("paymentRefMatches", () => {
  const order = {
    paymentRef: { checkoutId: "checkout-2" },
    paymentAttempts: [
      { paymentRef: { invoiceId: "invoice-1" } },
      { paymentRef: { checkoutId: "checkout-2" } },
    ],
  };

  test("accepts the attempt currently on the order", () => {
    assert.equal(paymentRefMatches(order, { checkoutId: "checkout-2" }), true);
  });

  test("accepts a superseded attempt, so a late webhook is still honoured", () => {
    assert.equal(paymentRefMatches(order, { invoiceId: "invoice-1" }), true);
  });

  test("refuses an invoice this order never started - the free-goods exploit", () => {
    assert.equal(paymentRefMatches(order, { invoiceId: "someone-elses" }), false);
  });

  test("refuses a webhook carrying no reference at all", () => {
    assert.equal(paymentRefMatches(order, {}), false);
  });

  test("tolerates an order with no attempt history", () => {
    assert.equal(paymentRefMatches({}, { invoiceId: "invoice-1" }), false);
    assert.equal(
        paymentRefMatches(
            { paymentRef: { invoiceId: "invoice-1" } }, { invoiceId: "invoice-1" }),
        true);
  });
});

describe("hasPendingAttempt", () => {
  const awaiting = (paymentMethod, startedMsAgo) => ({
    paymentStatus: "awaiting_confirmation",
    paymentMethod,
    lastPaymentAttemptAt: timestamp(Date.now() - startedMsAgo),
  });

  test("refuses a double-tap of the same method inside the window", () => {
    assert.equal(hasPendingAttempt(awaiting("MPESA", 1000), "MPESA"), true);
  });

  test("allows switching method immediately - that's a real user choice", () => {
    assert.equal(hasPendingAttempt(awaiting("MPESA", 1000), "PAYPAL"), false);
  });

  test("allows a deliberate retry once the window has passed", () => {
    assert.equal(
        hasPendingAttempt(
            awaiting("MPESA", DUPLICATE_ATTEMPT_WINDOW_MS + 1), "MPESA"),
        false);
  });

  test("never blocks an order that isn't awaiting confirmation", () => {
    assert.equal(
        hasPendingAttempt({ paymentStatus: "pending", paymentMethod: "MPESA" }, "MPESA"),
        false);
  });

  test("leaves a pre-timestamp order payable rather than deadlocked", () => {
    assert.equal(
        hasPendingAttempt(
            { paymentStatus: "awaiting_confirmation", paymentMethod: "MPESA" }, "MPESA"),
        false);
  });
});

describe("splitServiceFee", () => {
  test("takes exactly the platform's 7% rate, and the seller is owed retail less CJ's cost and the fee", () => {
    assert.equal(SERVICE_FEE_RATE, 0.07);
    const { serviceFeeAmountUsd, sellerRevenueUsd } = splitServiceFee(100, 40);
    assert.equal(serviceFeeAmountUsd, 7);
    assert.equal(sellerRevenueUsd, 53);
  });

  test("fee + supplier cost + seller revenue always reconstitute the subtotal exactly", () => {
    // Cents that don't divide evenly by the rate are the case most likely to
    // drift under naive rounding - assert the pieces still sum to the
    // original subtotal to the cent.
    for (const [subtotal, supplier] of [[0.01, 0], [1, 0.5], [9.99, 4.37], [33.33, 11.11], [1234.56, 600]]) {
      const { serviceFeeAmountUsd, sellerRevenueUsd } = splitServiceFee(subtotal, supplier);
      assert.equal(
          Math.round((serviceFeeAmountUsd + supplier + sellerRevenueUsd) * 100) / 100,
          subtotal);
    }
  });

  test("the fee is on the retail subtotal, not on the seller's margin", () => {
    assert.equal(splitServiceFee(100, 90).serviceFeeAmountUsd, 7);
  });

  test("a zero subtotal splits to zero, not NaN or a negative fee", () => {
    assert.deepEqual(
        splitServiceFee(0), { serviceFeeAmountUsd: 0, sellerRevenueUsd: 0 });
  });

  test("treats a negative or non-finite subtotal as zero rather than paying a seller for nothing", () => {
    assert.deepEqual(
        splitServiceFee(-50), { serviceFeeAmountUsd: 0, sellerRevenueUsd: 0 });
    assert.deepEqual(
        splitServiceFee(NaN), { serviceFeeAmountUsd: 0, sellerRevenueUsd: 0 });
    assert.deepEqual(
        splitServiceFee(undefined), { serviceFeeAmountUsd: 0, sellerRevenueUsd: 0 });
  });
});

describe("lineRefusal", () => {
  const line = (overrides) => ({
    supplierUnitPriceUsd: 10,
    retailUnitPriceUsd: 20,
    quantity: 1,
    available: undefined,
    ...overrides,
  });

  test("a priced, in-stock line is fine", () => {
    assert.equal(lineRefusal(line({ available: 5 })), null);
  });

  test("refuses a listing with no usable price", () => {
    assert.equal(lineRefusal(line({ retailUnitPriceUsd: 0 })), "no_price");
    assert.equal(lineRefusal(line({ retailUnitPriceUsd: NaN })), "no_price");
  });

  test("refuses a price that doesn't cover CJ's cost - the $1 listing of a $20 item", () => {
    assert.equal(lineRefusal(line({ retailUnitPriceUsd: 1, supplierUnitPriceUsd: 20 })), "below_cost");
  });

  test("the floor includes the fee: at cost, the fee would come out of Sellora's pocket", () => {
    assert.equal(lineRefusal(line({ retailUnitPriceUsd: 10, supplierUnitPriceUsd: 10 })), "below_cost");
    // 10.76 * 0.93 = 10.0068, which covers a $10 cost.
    assert.equal(lineRefusal(line({ retailUnitPriceUsd: 10.76, supplierUnitPriceUsd: 10 })), null);
  });

  test("refuses a variant CJ reports out of stock, or short of the quantity", () => {
    assert.equal(lineRefusal(line({ available: 0 })), "out_of_stock");
    assert.equal(lineRefusal(line({ available: 2, quantity: 3 })), "insufficient_stock");
  });

  test("unknown stock is not treated as none - getProductStock's contract", () => {
    assert.equal(lineRefusal(line({ available: undefined })), null);
    assert.equal(lineRefusal(line({ available: null })), null);
  });
});

describe("isExpired", () => {
  test("an order past expires_at is expired", () => {
    assert.equal(isExpired({ expiresAt: timestamp(NOW - 1) }, NOW), true);
  });

  test("an order inside its window is not", () => {
    assert.equal(isExpired({ expiresAt: timestamp(NOW + ORDER_TTL_MS) }, NOW), false);
  });

  test("an order from before expiry existed never expires", () => {
    assert.equal(isExpired({}, NOW), false);
  });
});

describe("validateOrderRequest", () => {
  const items = [{ pid: "p1", vid: "v1", quantity: 1 }];
  const address = { countryCode: "KE" };

  test("requires a storeId - a cart can no longer check out unattributed to a seller", () => {
    assert.throws(() => validateOrderRequest(items, address, undefined));
    assert.throws(() => validateOrderRequest(items, address, ""));
    assert.throws(() => validateOrderRequest(items, address, 42));
  });

  test("passes with a valid storeId and otherwise-valid items/address", () => {
    assert.doesNotThrow(() => validateOrderRequest(items, address, "store-1"));
  });
});
