import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  memoValidUntil,
  MEMO_TTL_MS,
  REFRESH_MARGIN_MS,
} from "../_shared/cjAuth.js";

const NOW = 1_700_000_000_000;
const isoIn = (ms) => new Date(NOW + ms).toISOString();

describe("memoValidUntil", () => {
  test("holds a long-lived token for the memo TTL, not for its full 15 days", () => {
    const days = 15 * 24 * 60 * 60 * 1000;
    assert.equal(memoValidUntil(isoIn(days), NOW), NOW + MEMO_TTL_MS);
  });

  test("never outlives the point the Firestore path would refresh the token", () => {
    // Ten minutes short of the refresh margin, so the token's own life binds
    // before the memo TTL does.
    const tenMinutes = 10 * 60 * 1000;
    assert.equal(
        memoValidUntil(isoIn(REFRESH_MARGIN_MS + tenMinutes), NOW),
        NOW + tenMinutes);
  });

  test("is already invalid for a token inside its refresh margin", () => {
    assert.ok(memoValidUntil(isoIn(REFRESH_MARGIN_MS / 2), NOW) <= NOW);
  });

  test("is already invalid for an expired token", () => {
    assert.ok(memoValidUntil(isoIn(-1000), NOW) < NOW);
  });

  test("falls back to the memo TTL when CJ sends no usable expiry", () => {
    for (const value of [undefined, null, "", "not a date"]) {
      assert.equal(memoValidUntil(value, NOW), NOW + MEMO_TTL_MS);
    }
  });
});
