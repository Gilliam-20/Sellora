const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const { ALERTS, buildEntry } = require("../lib/logging");

describe("ALERTS", () => {
  test("names are stable - log-based alert policies filter on these exact values", () => {
    assert.deepEqual(ALERTS, {
      CJ_PUSH_FAILED: "cj_push_failed",
      ORDER_NEEDS_RECONCILIATION: "order_needs_reconciliation",
      WEBHOOK_SIGNATURE_INVALID: "webhook_signature_invalid",
      PAYMENT_AMOUNT_MISMATCH: "payment_amount_mismatch",
      FX_FALLBACK: "fx_fallback",
      FX_STALE: "fx_stale",
      DELIVERY_EXCEPTION: "delivery_exception",
      REFUND_FAILED: "refund_failed",
    });
  });
});

describe("buildEntry", () => {
  test("carries the context a failed payment is debugged from", () => {
    assert.deepEqual(
        buildEntry("request_failed", {
          endpoint: "payOrderMpesa",
          orderId: "order-1",
          uid: "user-1",
        }),
        {
          event: "request_failed",
          endpoint: "payOrderMpesa",
          orderId: "order-1",
          uid: "user-1",
        },
    );
  });

  test("drops empty fields rather than logging nulls", () => {
    assert.deepEqual(
        buildEntry("e", { orderId: "o", uid: undefined, note: null, empty: "" }),
        { event: "e", orderId: "o" },
    );
  });

  test("keeps falsy-but-real values", () => {
    assert.deepEqual(
        buildEntry("e", { attempt: 0, parked: false }),
        { event: "e", attempt: 0, parked: false },
    );
  });

  test("flags an alert-worthy entry", () => {
    assert.equal(buildEntry("e", {}, { alert: true }).alert, true);
    assert.equal("alert" in buildEntry("e", {}), false);
  });

  test("attaches the error message", () => {
    const entry = buildEntry("e", { orderId: "o" }, { error: new Error("CJ balance too low") });
    assert.equal(entry.error, "CJ balance too low");
  });

  test("truncates a huge upstream error body instead of logging all of it", () => {
    const entry = buildEntry("e", { body: "x".repeat(5000) });
    assert.equal(entry.body.length, 1003);
    assert.ok(entry.body.endsWith("..."));
  });
});
