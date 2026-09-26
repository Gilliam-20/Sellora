import { describe, test, afterEach } from "node:test";
import assert from "node:assert/strict";
import { setDb } from "../_shared/db.js";
import { fulfillOrder } from "../_shared/orders.js";
import { resetAccessTokenMemo } from "../_shared/cjAuth.js";
import { setLogSink } from "../_shared/logging.js";
import { fakeDb } from "./fakeDb.js";

const quiet = { info() {}, warn() {}, error() {} };

/** An `orders` row as the service role reads it: paid for, never pushed. */
const orderRow = (overrides = {}) => ({
  id: "order-1",
  code: "SLR-ORDER1",
  buyer_id: "buyer-1",
  status: "pending",
  payment_status: "awaiting_confirmation",
  total: 30,
  total_kes: 3870,
  cj_order_status: "NOT_PUSHED",
  cj_push_attempts: 0,
  cj_push_claimed_at: null,
  shipping_address: { countryCode: "KE", line: "Nairobi" },
  fulfillment_items: [{ pid: "p1", vid: "v1", quantity: 1 }],
  ...overrides,
});

const realFetch = globalThis.fetch;

afterEach(() => {
  setDb(null);
  globalThis.fetch = realFetch;
  resetAccessTokenMemo();
});

describe("fulfillOrder's claim", () => {
  test("loses cleanly when another invocation changed the CJ state first", async () => {
    setLogSink(quiet);
    const db = fakeDb((call) => {
      if (call.op === "select") return { data: orderRow(), error: null };
      // The compare-and-set matched nothing: someone else holds the claim.
      if (call.op === "update") return { data: [], error: null };
      throw new Error(`unexpected ${call.op}`);
    });
    setDb(db);

    const result = await fulfillOrder("order-1");

    assert.equal(result.fulfilled, false);
    assert.equal(result.reason, "push_in_progress");
    const claim = db.calls.find((c) => c.op === "update");
    // The claim is conditioned on exactly the state it was decided from.
    assert.deepEqual(claim.filters, [
      ["eq", "id", "order-1"],
      ["eq", "cj_order_status", "NOT_PUSHED"],
      ["eq", "cj_push_attempts", 0],
    ]);
    assert.equal(claim.payload.cj_order_status, "PUSHING");
    assert.equal(claim.payload.cj_push_attempts, 1);
    assert.equal(claim.payload.payment_status, "paid");
    assert.equal(claim.payload.status, "processing");
    // Losing the race must not reach CJ, so there is no second update.
    assert.equal(db.calls.filter((c) => c.op === "update").length, 1);
  });

  test("records a CJ failure for the retry job instead of throwing", async () => {
    setLogSink(quiet);
    const db = fakeDb((call) => {
      if (call.table === "orders" && call.op === "select") {
        return { data: orderRow(), error: null };
      }
      if (call.table === "cj_auth_tokens") {
        return {
          data: {
            access_token: "token",
            access_token_expiry_date: new Date(Date.now() + 10 * 86400000).toISOString(),
          },
          error: null,
        };
      }
      if (call.table === "orders" && call.op === "update") {
        return { data: [{ id: "order-1" }], error: null };
      }
      throw new Error(`unexpected ${call.table} ${call.op}`);
    });
    setDb(db);
    // CJ refuses the order (an empty wallet, say).
    globalThis.fetch = () => Promise.resolve(new Response(
        JSON.stringify({ code: 1600100, result: false, message: "Insufficient balance" }),
        { status: 200 }));

    const result = await fulfillOrder("order-1");

    assert.equal(result.paid, true);
    assert.equal(result.fulfilled, false);
    assert.equal(result.cjOrderStatus, "FAILED");
    const updates = db.calls.filter((c) => c.op === "update");
    assert.equal(updates.length, 2);
    assert.equal(updates[1].payload.cj_order_status, "FAILED");
    assert.match(updates[1].payload.cj_order_error, /Insufficient balance/);
  });

  test("leaves an already-pushed order alone", async () => {
    const db = fakeDb((call) => {
      if (call.op === "select") {
        return { data: orderRow({ payment_status: "paid", cj_order_status: "PUSHED" }), error: null };
      }
      throw new Error(`unexpected ${call.op}`);
    });
    setDb(db);

    const result = await fulfillOrder("order-1");

    assert.equal(result.fulfilled, true);
    assert.equal(result.alreadyHandled, true);
    assert.equal(db.calls.length, 1);
  });

  test("never re-marks a refunded order paid (a late webhook retry)", async () => {
    const db = fakeDb((call) => {
      if (call.op === "select") {
        return { data: orderRow({ payment_status: "refunded", status: "cancelled" }), error: null };
      }
      throw new Error(`unexpected ${call.op}`);
    });
    setDb(db);

    const result = await fulfillOrder("order-1");

    assert.equal(result.fulfilled, false);
    assert.equal(result.reason, "refunded");
    assert.equal(db.calls.length, 1);
  });

  test("does not walk a seller-advanced status back to processing", async () => {
    setLogSink(quiet);
    const db = fakeDb((call) => {
      if (call.op === "select") return { data: orderRow({ status: "shipped" }), error: null };
      return { data: [], error: null };
    });
    setDb(db);

    await fulfillOrder("order-1");

    const claim = db.calls.find((c) => c.op === "update");
    assert.equal("status" in claim.payload, false);
  });
});
