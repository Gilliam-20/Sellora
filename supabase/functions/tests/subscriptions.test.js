import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  isPayable, billingRefMatches, subscribeRefusal, downgradeRefusal, retiredPlanRefusal,
} from "../_shared/subscriptions.js";

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

describe("downgradeRefusal", () => {
  const starter = { name: "Starter", listing_limit: 25 };

  test("a plan with room for every listing is fine", () => {
    assert.equal(downgradeRefusal(starter, 25), null);
    assert.equal(downgradeRefusal(starter, 0), null);
  });

  test("an unlimited plan is always fine", () => {
    assert.equal(downgradeRefusal({ name: "Scale", listing_limit: -1 }, 5000), null);
  });

  test("a plan below what's listed says how many to unlist", () => {
    assert.equal(downgradeRefusal(starter, 26),
        "Starter allows 25 listed products and you have 26. Unlist 1 product first, then switch.");
    assert.match(downgradeRefusal(starter, 40), /Unlist 15 products first/);
  });

  test("a numeric limit sent as a string still counts", () => {
    assert.match(downgradeRefusal({ name: "Starter", listing_limit: "25" }, 30), /Unlist 5/);
  });
});

describe("retiredPlanRefusal", () => {
  const retired = { name: "Starter", is_active: false };

  test("an active plan is always sold", () => {
    assert.equal(retiredPlanRefusal({ name: "Growth", is_active: true }, null, "growth"), null);
  });

  test("a plan from before is_active existed counts as active", () => {
    assert.equal(retiredPlanRefusal({ name: "Growth" }, null, "growth"), null);
  });

  test("a retired plan is refused to a new subscriber", () => {
    assert.equal(retiredPlanRefusal(retired, null, "starter"),
        "Starter is no longer offered. Choose another plan.");
  });

  test("and to a seller switching from another plan", () => {
    assert.ok(retiredPlanRefusal(retired, "growth", "starter"));
  });

  test("but a seller already on it may renew", () => {
    assert.equal(retiredPlanRefusal(retired, "starter", "starter"), null);
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
