const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const {
  pivotRate,
  rateAgeMs,
  rateStaleness,
  STALE_ALERT_MS,
  MAX_STALENESS_MS,
} = require("../lib/fx");

// pivotRate is pure - it only reads the plain object handed to it - so
// these tests exercise it directly without touching Firestore or the live
// rate provider.
const usdBaseDoc = {
  base: "USD",
  rates: { KES: 129, EUR: 0.92, GBP: 0.79 },
};

describe("pivotRate", () => {
  test("same currency is always a 1:1 rate", () => {
    assert.equal(pivotRate(usdBaseDoc, "KES", "KES"), 1);
    assert.equal(pivotRate(usdBaseDoc, "USD", "USD"), 1);
  });

  test("base -> quote uses the cached rate directly", () => {
    assert.equal(pivotRate(usdBaseDoc, "USD", "KES"), 129);
    assert.equal(pivotRate(usdBaseDoc, "USD", "EUR"), 0.92);
  });

  test("quote -> base is the inverse of the cached rate", () => {
    assert.equal(pivotRate(usdBaseDoc, "KES", "USD"), 1 / 129);
    assert.equal(pivotRate(usdBaseDoc, "GBP", "USD"), 1 / 0.79);
  });

  test("quote -> quote pivots through the base currency", () => {
    const rate = pivotRate(usdBaseDoc, "KES", "EUR");
    assert.ok(Math.abs(rate - (0.92 / 129)) < 1e-9);

    const inverse = pivotRate(usdBaseDoc, "EUR", "GBP");
    assert.ok(Math.abs(inverse - (0.79 / 0.92)) < 1e-9);
  });

  test("throws when the base-side rate is missing", () => {
    const sparseDoc = { base: "USD", rates: { KES: 129 } };
    assert.throws(() => pivotRate(sparseDoc, "USD", "GBP"));
    assert.throws(() => pivotRate(sparseDoc, "GBP", "USD"));
  });

  test("throws when a pivot leg is missing for quote -> quote", () => {
    const sparseDoc = { base: "USD", rates: { KES: 129 } };
    assert.throws(() => pivotRate(sparseDoc, "KES", "EUR"));
  });
});

describe("rateAgeMs", () => {
  const now = 1_700_000_000_000;

  test("reads a Firestore Timestamp", () => {
    assert.equal(rateAgeMs({ toMillis: () => now - 5000 }, now), 5000);
  });

  test("reads the Date the refresh path returns before a round trip", () => {
    assert.equal(rateAgeMs(new Date(now - 5000), now), 5000);
  });

  test("treats a missing or unusable timestamp as infinitely old", () => {
    for (const value of [undefined, null, 0, "", "nope", {}]) {
      assert.equal(rateAgeMs(value, now), Infinity);
    }
  });
});

describe("rateStaleness", () => {
  const hours = (n) => n * 60 * 60 * 1000;

  test("a rate refreshed today is fresh", () => {
    assert.equal(rateStaleness(hours(1)), "fresh");
    assert.equal(rateStaleness(hours(23)), "fresh");
  });

  test("past the daily cache window it's due a refresh but still usable", () => {
    assert.equal(rateStaleness(hours(25)), "aging");
  });

  test("a rate this old means the refresh has been failing unnoticed", () => {
    assert.equal(rateStaleness(STALE_ALERT_MS), "stale");
    assert.equal(rateStaleness(STALE_ALERT_MS + hours(1)), "stale");
  });

  test("past the ceiling it's expired - pricing from it would mis-charge", () => {
    assert.equal(rateStaleness(MAX_STALENESS_MS), "expired");
    assert.equal(rateStaleness(Infinity), "expired");
  });
});
