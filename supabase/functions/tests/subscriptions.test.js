import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { isPayable, billingRefMatches, subscribeRefusal } from "../_shared/subscriptions.js";

describe("subscribeRefusal", () => {
  test("an approved or pending seller may subscribe", () => {
    assert.equal(subscribeRefusal({ role: "seller", seller_status: "active" }), null);
    assert.equal(subscribeRefusal({ role: "seller", seller_status: "pendingApproval" }), null);
  });

  test("a buyer may not - paying would otherwise make them a seller", () => {
    assert.match(subscribeRefusal({ role: "buyer" }), /Only seller/);
  });

  test("a suspended seller may not pay their way out", () => {
    assert.match(subscribeRefusal({ role: "seller", seller_status: "suspended" }), /suspended/);
  });

  test("a missing profile may not", () => {
    assert.ok(subscribeRefusal(null));
  });
});

describe("isPayable", () => {
  test("a freshly-created pending entry is payable", () => {
    assert.equal(isPayable({ status: "pending" }), true);
  });

  test("an already-paid entry is not payable - a webhook retry must be a no-op", () => {
    assert.equal(isPayable({ status: "paid" }), false);
  });

  test("a failed entry is not payable", () => {
    assert.equal(isPayable({ status: "failed" }), false);
  });

  test("a missing entry is not payable", () => {
    assert.equal(isPayable(null), false);
    assert.equal(isPayable(undefined), false);
  });
});

describe("billingRefMatches", () => {
  test("matches an invoiceId this entry actually started", () => {
    const entry = { paymentRef: { invoiceId: "inv-1" } };
    assert.equal(billingRefMatches(entry, { invoiceId: "inv-1" }), true);
  });

  test("refuses a genuinely-completed invoice bound to a different entry - the anti-fraud check", () => {
    const entry = { paymentRef: { invoiceId: "inv-1" } };
    assert.equal(billingRefMatches(entry, { invoiceId: "attacker-inv" }), false);
  });

  test("refuses an entry that never started any payment attempt", () => {
    assert.equal(billingRefMatches({}, { invoiceId: "inv-1" }), false);
  });

  test("refuses a missing entry", () => {
    assert.equal(billingRefMatches(null, { invoiceId: "inv-1" }), false);
  });

  test("matches on checkoutId the same way", () => {
    const entry = { paymentRef: { checkoutId: "chk-1" } };
    assert.equal(billingRefMatches(entry, { checkoutId: "chk-1" }), true);
  });
});
