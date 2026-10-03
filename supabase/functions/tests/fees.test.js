import { afterEach, describe, test } from "node:test";
import assert from "node:assert/strict";
import {
  DEFAULT_FEE_SETTINGS,
  clearFeeSettingsCache,
  getFeeSettings,
  normalizeFeeSettings,
} from "../_shared/fees.js";
import { setDb } from "../_shared/db.js";
import { fakeDb } from "./fakeDb.js";

afterEach(() => {
  setDb(null);
  clearFeeSettingsCache();
});

describe("normalizeFeeSettings", () => {
  test("defaults to 7% on the goods only", () => {
    assert.deepEqual(normalizeFeeSettings(null), DEFAULT_FEE_SETTINGS);
    assert.deepEqual(normalizeFeeSettings({}),
        { serviceFeeRate: 0.07, chargeOnShipping: false });
  });

  test("keeps a configured rate and the shipping switch", () => {
    assert.deepEqual(normalizeFeeSettings({ serviceFeeRate: 0.05, chargeOnShipping: true }),
        { serviceFeeRate: 0.05, chargeOnShipping: true });
    assert.equal(normalizeFeeSettings({ serviceFeeRate: 0 }).serviceFeeRate, 0);
  });

  test("an out-of-range or unreadable rate falls back to the default", () => {
    for (const bad of [-0.01, 0.31, 7, "abc", NaN, Infinity]) {
      assert.equal(normalizeFeeSettings({ serviceFeeRate: bad }).serviceFeeRate, 0.07);
    }
  });

  test("only a real true turns on the shipping fee", () => {
    assert.equal(normalizeFeeSettings({ chargeOnShipping: "true" }).chargeOnShipping, false);
  });
});

describe("getFeeSettings", () => {
  test("reads service_fee_settings() and caches it", async () => {
    const db = fakeDb(() => ({ data: { serviceFeeRate: 0.06, chargeOnShipping: false }, error: null }));
    setDb(db);
    assert.deepEqual(await getFeeSettings(), { serviceFeeRate: 0.06, chargeOnShipping: false });
    await getFeeSettings();
    assert.equal(db.calls.length, 1);
    assert.equal(db.calls[0].rpc, "service_fee_settings");
  });

  test("a database error throws rather than guessing a fee", async () => {
    setDb(fakeDb(() => ({ data: null, error: { code: "XX000", message: "down" } })));
    await assert.rejects(getFeeSettings(), /Database error/);
  });
});
