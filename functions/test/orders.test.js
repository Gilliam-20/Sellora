const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const {
  decidePushClaim,
  paymentRefMatches,
  hasPendingAttempt,
  MAX_FULFILLMENT_ATTEMPTS,
  PUSH_CLAIM_STALE_MS,
  DUPLICATE_ATTEMPT_WINDOW_MS,
} = require("../lib/orders");

// Firestore hands timestamps back as objects with toMillis(), which is what
// the state machine reads.
const timestamp = (millis) => ({ toMillis: () => millis });
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
    paymentStatus: "AWAITING_CONFIRMATION",
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
            { paymentStatus: "AWAITING_CONFIRMATION", paymentMethod: "MPESA" }, "MPESA"),
        false);
  });
});
