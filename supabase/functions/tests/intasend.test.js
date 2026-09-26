import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  mpesaAmountError,
  verifyAmount,
  MPESA_MIN_KES,
  MPESA_MAX_KES,
} from "../_shared/intasendApi.js";

describe("mpesaAmountError", () => {
  test("accepts an ordinary order total", () => {
    assert.equal(mpesaAmountError(2500), null);
    assert.equal(mpesaAmountError(MPESA_MIN_KES), null);
    assert.equal(mpesaAmountError(MPESA_MAX_KES), null);
  });

  test("rejects an amount over Safaricom's per-transaction cap", () => {
    const message = mpesaAmountError(MPESA_MAX_KES + 1);
    assert.ok(message);
    // The customer needs to know what to do instead, not just that it failed.
    assert.match(message, /pay by card/);
  });

  test("rejects an amount below the M-Pesa minimum", () => {
    assert.match(mpesaAmountError(MPESA_MIN_KES - 1), /start at KES/);
  });

  test("rejects an order with no payable amount", () => {
    for (const value of [0, -1, null, undefined, NaN, "abc"]) {
      assert.ok(mpesaAmountError(value));
    }
  });

  test("reads a numeric string total", () => {
    assert.equal(mpesaAmountError("2500"), null);
  });
});

describe("verifyAmount", () => {
  const expected = { amount: 2500, currency: "KES" };

  test("passes when IntaSend collected what the order asked for", () => {
    const result = verifyAmount(
        { invoice: { net_amount: 2500, currency: "KES" } }, expected);
    assert.equal(result.ok, true);
    assert.deepEqual(result.actual, { value: 2500, currency: "KES" });
  });

  test("fails on a short payment", () => {
    assert.equal(
        verifyAmount({ invoice: { net_amount: 10, currency: "KES" } }, expected).ok,
        false);
  });

  test("fails on the same number in a different currency", () => {
    assert.equal(
        verifyAmount({ invoice: { net_amount: 2500, currency: "USD" } }, expected).ok,
        false);
  });

  test("fails open when the amount can't be located, and says so", () => {
    // The invoice binding is the real control; blocking a genuine payment on
    // an unverified field path would be worse. The caller logs this case.
    const result = verifyAmount({ invoice: { state: "COMPLETE" } }, expected);
    assert.equal(result.ok, true);
    assert.equal(result.actual, null);
  });
});
