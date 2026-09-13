const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const {
  decideRefund,
  refundedState,
  chargedAmount,
  REFUND_CLAIM_STALE_MS,
} = require("../lib/refunds");
const { normalizeRefundReason } = require("../lib/intasendApi");

const timestamp = (millis) => ({ toMillis: () => millis });
const NOW = 1_700_000_000_000;

/** A paid M-Pesa order: charged KES 3,870 against a KES 30 / USD order. */
const mpesaOrder = (overrides = {}) => ({
  uid: "user-1",
  paymentStatus: "paid",
  paymentProvider: "INTASEND",
  paymentMethod: "MPESA",
  paymentRef: { invoiceId: "inv-1" },
  currency: "KES",
  totalAmount: 3870,
  totalKes: 3870,
  totalUsd: 30,
  cjOrderStatus: "NOT_PUSHED",
  refundedAmount: 0,
  ...overrides,
});

/** A paid PayPal order: charged USD 30, whatever its KES equivalent is. */
const paypalOrder = (overrides = {}) => ({
  uid: "user-1",
  paymentStatus: "paid",
  paymentProvider: "PAYPAL",
  paymentMethod: "PAYPAL",
  paymentRef: { paypalOrderId: "pp-1", paypalCaptureId: "cap-1" },
  currency: "USD",
  totalAmount: 30,
  totalKes: 3870,
  totalUsd: 30,
  cjOrderStatus: "NOT_PUSHED",
  refundedAmount: 0,
  ...overrides,
});

describe("chargedAmount", () => {
  test("refunds IntaSend in KES - what it actually collected, not the order's display total", () => {
    assert.deepEqual(
        chargedAmount(mpesaOrder({ currency: "USD", totalAmount: 30 })),
        { amount: 3870, currency: "KES" },
    );
  });

  test("refunds PayPal in the order's own currency", () => {
    assert.deepEqual(chargedAmount(paypalOrder()), { amount: 30, currency: "USD" });
    assert.deepEqual(
        chargedAmount(paypalOrder({ currency: "GBP", totalAmount: 24.5 })),
        { amount: 24.5, currency: "GBP" },
    );
  });

  test("an order with no provider has nothing to refund through", () => {
    assert.equal(chargedAmount({ paymentProvider: null }), null);
  });
});

describe("decideRefund", () => {
  test("refunds the whole charge when no amount is asked for", () => {
    const decision = decideRefund(mpesaOrder(), { now: NOW });
    assert.equal(decision.ok, true);
    assert.equal(decision.amount, 3870);
    assert.equal(decision.currency, "KES");
    assert.equal(decision.provider, "INTASEND");
    assert.equal(decision.full, true);
  });

  test("refunds a partial amount and doesn't call it full", () => {
    const decision = decideRefund(mpesaOrder(), { amount: 1000, now: NOW });
    assert.equal(decision.ok, true);
    assert.equal(decision.amount, 1000);
    assert.equal(decision.full, false);
  });

  test("refuses an order that was never paid", () => {
    const decision = decideRefund(
        mpesaOrder({ paymentStatus: "pending" }), { now: NOW });
    assert.deepEqual(decision, { ok: false, reason: "not_paid" });
  });

  test("refuses one already refunded in full", () => {
    const decision = decideRefund(
        mpesaOrder({ paymentStatus: "refunded", refundedAmount: 3870 }),
        { now: NOW });
    assert.deepEqual(decision, { ok: false, reason: "already_refunded" });
  });

  test("refunds only what's left after a partial refund", () => {
    const decision = decideRefund(
        mpesaOrder({ paymentStatus: "partially_refunded", refundedAmount: 1000 }),
        { now: NOW });
    assert.equal(decision.ok, true);
    assert.equal(decision.amount, 2870);
    // Not "full": some of this order was refunded on a separate occasion.
    assert.equal(decision.full, false);
  });

  test("refuses more than the amount left", () => {
    const decision = decideRefund(
        mpesaOrder({ refundedAmount: 3000 }), { amount: 1000, now: NOW });
    assert.deepEqual(decision, { ok: false, reason: "exceeds_remaining" });
  });

  test("refuses a zero, negative or unparseable amount", () => {
    for (const amount of [0, -5, "abc", NaN]) {
      assert.equal(
          decideRefund(mpesaOrder(), { amount, now: NOW }).reason,
          "invalid_amount",
          `amount ${amount} must be refused`,
      );
    }
  });

  test("refuses a second refund while one is in flight - a double click is not two refunds", () => {
    const decision = decideRefund(
        mpesaOrder({
          refundStatus: "PROCESSING",
          refundClaimedAt: timestamp(NOW - 1000),
        }),
        { now: NOW });
    assert.deepEqual(decision, { ok: false, reason: "refund_in_progress" });
  });

  test("reclaims a refund claim left behind by a crashed invocation", () => {
    const decision = decideRefund(
        mpesaOrder({
          refundStatus: "PROCESSING",
          refundClaimedAt: timestamp(NOW - REFUND_CLAIM_STALE_MS - 1),
        }),
        { now: NOW });
    assert.equal(decision.ok, true);
  });

  test("a failed refund can be retried", () => {
    const decision = decideRefund(
        mpesaOrder({ refundStatus: "FAILED", refundError: "boom" }), { now: NOW });
    assert.equal(decision.ok, true);
  });

  test("cancels an order that never reached CJ", () => {
    assert.equal(decideRefund(mpesaOrder(), { now: NOW }).cancelOrder, true);
  });

  test("leaves an order already with CJ live - the goods are on their way", () => {
    const decision = decideRefund(
        mpesaOrder({ cjOrderStatus: "PUSHED" }), { now: NOW });
    assert.equal(decision.ok, true);
    assert.equal(decision.cancelOrder, false);
  });

  test("a partial refund never cancels the order", () => {
    assert.equal(
        decideRefund(mpesaOrder(), { amount: 500, now: NOW }).cancelOrder,
        false,
    );
  });

  test("refuses an order whose total can't be read rather than refunding zero", () => {
    const decision = decideRefund(
        mpesaOrder({ totalKes: null }), { now: NOW });
    assert.deepEqual(decision, { ok: false, reason: "no_charge_to_refund" });
  });
});

describe("refundedState", () => {
  test("a full refund settles the order as refunded", () => {
    const order = mpesaOrder();
    const state = refundedState(order, decideRefund(order, { now: NOW }));
    assert.deepEqual(state, {
      refundedAmount: 3870,
      paymentStatus: "refunded",
      status: "cancelled",
    });
  });

  test("a partial refund leaves the order partially refunded and live", () => {
    const order = mpesaOrder();
    const state = refundedState(order, decideRefund(order, { amount: 870, now: NOW }));
    assert.deepEqual(state, {
      refundedAmount: 870,
      paymentStatus: "partially_refunded",
    });
  });

  test("partial refunds accumulate to fully refunded", () => {
    const order = mpesaOrder({
      paymentStatus: "partially_refunded",
      refundedAmount: 3000,
    });
    const state = refundedState(order, decideRefund(order, { now: NOW }));
    assert.equal(state.refundedAmount, 3870);
    assert.equal(state.paymentStatus, "refunded");
  });

  test("keeps money arithmetic to the cent rather than accumulating float drift", () => {
    const order = paypalOrder({ totalAmount: 30, refundedAmount: 10.1 });
    const state = refundedState(order, decideRefund(order, { amount: 0.2, now: NOW }));
    assert.equal(state.refundedAmount, 10.3);
  });
});

describe("normalizeRefundReason", () => {
  test("passes through the reasons IntaSend accepts, whatever the casing", () => {
    assert.equal(normalizeRefundReason("Duplicate"), "Duplicate");
    assert.equal(normalizeRefundReason("requested by customer"), "Requested by customer");
  });

  test("falls back to Other rather than letting IntaSend reject the refund", () => {
    assert.equal(normalizeRefundReason("cj out of stock"), "Other");
    assert.equal(normalizeRefundReason(undefined), "Other");
  });
});
