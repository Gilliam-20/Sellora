import { afterEach, describe, test } from "node:test";
import assert from "node:assert/strict";
import { alertNotice, assessListing, syncListings } from "../_shared/listingSync.js";
import { setDb } from "../_shared/db.js";
import { setLogSink } from "../_shared/logging.js";
import { fakeDb } from "./fakeDb.js";

afterEach(() => setDb(null));

const cj = (...prices) => prices.map(([vid, supplierPriceUsd]) => ({ vid, supplierPriceUsd }));

describe("assessListing", () => {
  test("a price that covers the dearest enabled variant plus the fee is fine", () => {
    const r = assessListing(
        { sell_price: 20, variants: [{ vid: "a" }, { vid: "b" }] },
        cj(["a", 10], ["b", 18.6]));
    // 20 * 0.93 = 18.60, exactly the floor.
    assert.equal(r.alert, null);
    assert.equal(r.costPrice, 18.6);
  });

  test("a CJ cost rise past the floor is below_cost", () => {
    const r = assessListing(
        { sell_price: 20, variants: [{ vid: "a" }] }, cj(["a", 18.61]));
    assert.equal(r.alert, "below_cost");
  });

  test("a disabled variant doesn't count against the price", () => {
    const r = assessListing(
        { sell_price: 20, variants: [{ vid: "a" }, { vid: "b", enabled: false }] },
        cj(["a", 10], ["b", 99]));
    assert.equal(r.alert, null);
    assert.equal(r.costPrice, 10);
  });

  test("refreshes each variant's costPrice and keeps its other fields", () => {
    const r = assessListing(
        { sell_price: 50, variants: [{ vid: "a", sku: "S-A", costPrice: 5 }, { vid: "gone", costPrice: 7 }] },
        cj(["a", 12]));
    assert.deepEqual(r.variants, [{ vid: "a", sku: "S-A", costPrice: 12 }, { vid: "gone", costPrice: 7 }]);
  });

  test("no enabled variant left at CJ is unavailable", () => {
    assert.equal(assessListing({ sell_price: 20, variants: [{ vid: "a" }] }, cj(["z", 5])).alert, "unavailable");
    assert.equal(assessListing({ sell_price: 20, variants: [] }, []).alert, "unavailable");
  });

  test("a CJ price it can't read is not a zero cost", () => {
    const r = assessListing({ sell_price: 20, variants: [{ vid: "a" }] }, cj(["a", null]));
    assert.equal(r.alert, "unavailable");
    assert.equal(r.costPrice, null);
  });

  test("a listing without its own variants is priced against all of CJ's", () => {
    assert.equal(assessListing({ sell_price: 10, variants: [] }, cj(["a", 5], ["b", 9.5])).alert, "below_cost");
  });
});

describe("alertNotice", () => {
  test("fits the notification length caps even for a long title", () => {
    const n = alertNotice("below_cost", { title: "x".repeat(600), sell_price: 20 }, 19);
    assert.ok(n.title.length <= 200 && n.message.length <= 2000);
    assert.match(n.message, /\$19\.00.*\$20\.00/);
  });
});

describe("syncListings", () => {
  const run = (rows, cjApi) => {
    const db = fakeDb((c) => {
      if (c.table === "products" && c.op === "select" && c.columns === "id") {
        return { data: rows.map((r) => ({ id: r.id })), error: null };
      }
      if (c.table === "products" && c.op === "select") {
        const pid = c.filters.find((f) => f[0] === "eq" && f[1] === "id")[2];
        return { data: rows.filter((r) => r.id === pid), error: null };
      }
      return { data: null, error: null };
    });
    setDb(db);
    return { db, done: syncListings({ cjApi, wait: () => Promise.resolve(), fees: async () => ({ serviceFeeRate: 0.07 }) }) };
  };
  const listing = (over) => ({
    store_id: "s1", id: "p1", seller_id: "seller-1", title: "Lamp",
    sell_price: 20, variants: [{ vid: "a" }], supplier_alert: null, ...over,
  });

  test("asks CJ once per product, however many stores list it", async () => {
    const asked = [];
    const { done } = run([listing(), listing({ store_id: "s2", seller_id: "seller-2" })], {
      getVariantPrices: (pid) => { asked.push(pid); return Promise.resolve(cj(["a", 10])); },
    });
    const summary = await done;
    assert.deepEqual(asked, ["p1"]);
    assert.equal(summary.listings, 2);
  });

  test("refreshes the cost and notifies the seller once, on a new alert", async () => {
    const { db, done } = run([listing()], { getVariantPrices: () => Promise.resolve(cj(["a", 19])) });
    const summary = await done;
    const update = db.calls.find((c) => c.op === "update");
    assert.equal(update.payload.cost_price, 19);
    assert.equal(update.payload.supplier_alert, "below_cost");
    const note = db.calls.find((c) => c.table === "notifications");
    assert.equal(note.payload.recipient_id, "seller-1");
    assert.equal(summary.alerts, 1);
  });

  test("an alert already raised isn't sent again", async () => {
    const { db, done } = run([listing({ supplier_alert: "below_cost" })],
        { getVariantPrices: () => Promise.resolve(cj(["a", 19])) });
    await done;
    assert.equal(db.calls.filter((c) => c.table === "notifications").length, 0);
  });

  test("a fixed price clears the alert", async () => {
    const { db, done } = run([listing({ supplier_alert: "below_cost", sell_price: 30 })],
        { getVariantPrices: () => Promise.resolve(cj(["a", 19])) });
    const summary = await done;
    assert.equal(db.calls.find((c) => c.op === "update").payload.supplier_alert, null);
    assert.equal(summary.cleared, 1);
  });

  test("a CJ failure changes no alert and never unlists", async () => {
    const previous = setLogSink({ info() {}, warn() {}, error() {} });
    try {
      const { db, done } = run([listing({ supplier_alert: "below_cost" })],
          { getVariantPrices: () => Promise.reject(new Error("CJ down")) });
      const summary = await done;
      const updates = db.calls.filter((c) => c.op === "update");
      assert.equal(summary.failed, 1);
      assert.equal(updates.length, 1);
      assert.deepEqual(Object.keys(updates[0].payload), ["supplier_checked_at"]);
      assert.ok(!db.calls.some((c) => c.payload && "is_listed" in c.payload));
    } finally {
      setLogSink(previous);
    }
  });
});
