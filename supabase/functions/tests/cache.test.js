import { test, describe, beforeEach } from "node:test";
import assert from "node:assert/strict";
import {
  getCached,
  setCached,
  withCache,
  cacheSize,
  clearCache,
  MAX_ENTRIES,
} from "../_shared/cache.js";

describe("cache", () => {
  beforeEach(() => clearCache());

  test("serves a stored value back", () => {
    setCached("k", { a: 1 }, 60000);
    assert.deepEqual(getCached("k"), { a: 1 });
  });

  test("treats an elapsed TTL as a miss and drops the entry", () => {
    setCached("k", "v", -1);
    assert.equal(getCached("k"), undefined);
    assert.equal(cacheSize(), 0);
  });

  test("withCache calls the producer once, then serves the cached value", async () => {
    let calls = 0;
    const produce = async () => {
      calls++;
      return "value";
    };
    assert.equal(await withCache("k", 60000, produce), "value");
    assert.equal(await withCache("k", 60000, produce), "value");
    assert.equal(calls, 1);
  });

  test("never grows past the entry cap", () => {
    for (let i = 0; i < MAX_ENTRIES + 50; i++) {
      setCached(`k${i}`, i, 60000);
    }
    assert.equal(cacheSize(), MAX_ENTRIES);
  });

  test("evicts the least recently used entry, not the most useful one", () => {
    for (let i = 0; i < MAX_ENTRIES; i++) setCached(`k${i}`, i, 60000);
    // A read is what makes k0 recently used - without that it would be first
    // out, since it was inserted first.
    getCached("k0");
    setCached("overflow", true, 60000);

    assert.equal(getCached("k0"), 0);
    assert.equal(getCached("k1"), undefined);
    assert.equal(cacheSize(), MAX_ENTRIES);
  });

  test("re-caching a key doesn't count as a second entry", () => {
    setCached("k", 1, 60000);
    setCached("k", 2, 60000);
    assert.equal(cacheSize(), 1);
    assert.equal(getCached("k"), 2);
  });
});
