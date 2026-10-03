import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  REGION_CONFIG, SHIPPING_ZONES, resolveRegion, storeShipsTo,
} from "../_shared/regions.js";

describe("REGION_CONFIG", () => {
  test("maps Kenya to the kenya region in KES", () => {
    assert.deepEqual(REGION_CONFIG.KE, { region: "kenya", currency: "KES" });
  });

  test("maps the US to the us region in USD", () => {
    assert.deepEqual(REGION_CONFIG.US, { region: "us", currency: "USD" });
  });

  test("maps the UK to the uk region in GBP", () => {
    assert.deepEqual(REGION_CONFIG.GB, { region: "uk", currency: "GBP" });
  });

  test("maps EU member states to the eu region in EUR", () => {
    const eu = { region: "eu", currency: "EUR" };
    assert.deepEqual(REGION_CONFIG.DE, eu);
    assert.deepEqual(REGION_CONFIG.FR, eu);
  });
});

describe("resolveRegion", () => {
  const kenya = { region: "kenya", currency: "KES" };
  const usFallback = { region: "us", currency: "USD" };

  test("resolves a known country code", () => {
    assert.deepEqual(resolveRegion("KE"), kenya);
  });

  test("is case-insensitive", () => {
    assert.deepEqual(resolveRegion("ke"), kenya);
  });

  test("falls back to us/USD for an unrecognized country code", () => {
    assert.deepEqual(resolveRegion("ZZ"), usFallback);
  });

  test("falls back to us/USD for missing input", () => {
    assert.deepEqual(resolveRegion(undefined), usFallback);
  });
});

describe("storeShipsTo", () => {
  test("ships to a country in one of the store's zones", () => {
    assert.equal(storeShipsTo(["kenya"], "KE"), true);
    assert.equal(storeShipsTo(["kenya", "eu"], "de"), true);
  });

  test("refuses a country outside the store's zones", () => {
    assert.equal(storeShipsTo(["kenya"], "US"), false);
    assert.equal(storeShipsTo(["us", "uk"], "FR"), false);
  });

  test("refuses an unconfigured country even though it would price as US", () => {
    assert.equal(storeShipsTo(SHIPPING_ZONES, "ZZ"), false);
    assert.equal(storeShipsTo(["us"], "CA"), false);
  });

  test("treats a store with no zones as shipping to every zone", () => {
    assert.equal(storeShipsTo([], "GB"), true);
    assert.equal(storeShipsTo(null, "KE"), true);
  });

  test("every zone is a region some country resolves to", () => {
    const regions = new Set(Object.values(REGION_CONFIG).map((c) => c.region));
    assert.deepEqual(new Set(SHIPPING_ZONES), regions);
  });
});
