const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const {
  clampPage,
  clampPageSize,
  sanitizeKeyword,
  sanitizeId,
  MAX_PAGE,
  MAX_PAGE_SIZE,
  DEFAULT_PAGE_SIZE,
  MAX_KEYWORD_LENGTH,
} = require("../lib/params");

describe("clampPageSize", () => {
  test("caps the scrape-sized page that went straight to CJ before", () => {
    assert.equal(clampPageSize("100000"), MAX_PAGE_SIZE);
  });

  test("passes a normal app-sized page through untouched", () => {
    assert.equal(clampPageSize("20"), 20);
    assert.equal(clampPageSize(1), 1);
  });

  test("falls back to the default for anything unusable", () => {
    for (const value of [undefined, null, "", "abc", NaN, {}]) {
      assert.equal(clampPageSize(value), DEFAULT_PAGE_SIZE);
    }
  });

  test("refuses zero and negative sizes", () => {
    assert.equal(clampPageSize("0"), 1);
    assert.equal(clampPageSize("-5"), 1);
  });

  test("truncates a fractional size rather than passing it to CJ", () => {
    assert.equal(clampPageSize("12.9"), 12);
  });
});

describe("clampPage", () => {
  test("caps deep paging, which is how a catalog gets enumerated", () => {
    assert.equal(clampPage("999999"), MAX_PAGE);
  });

  test("defaults to the first page", () => {
    assert.equal(clampPage(undefined), 1);
    assert.equal(clampPage("nope"), 1);
    assert.equal(clampPage("0"), 1);
    assert.equal(clampPage("-3"), 1);
  });
});

describe("sanitizeKeyword", () => {
  test("trims and collapses whitespace, so cache keys can't be padded apart", () => {
    assert.equal(sanitizeKeyword("  wireless   earbuds "), "wireless earbuds");
  });

  test("caps length", () => {
    const long = "a".repeat(MAX_KEYWORD_LENGTH + 100);
    assert.equal(sanitizeKeyword(long).length, MAX_KEYWORD_LENGTH);
  });

  test("returns an empty string for a non-string, never undefined", () => {
    for (const value of [undefined, null, 42, {}, []]) {
      assert.equal(sanitizeKeyword(value), "");
    }
  });
});

describe("sanitizeId", () => {
  test("accepts the id shapes CJ actually uses", () => {
    assert.equal(sanitizeId("1EA2F0F0-1234-4A11-9E1A-0C1"), "1EA2F0F0-1234-4A11-9E1A-0C1");
    assert.equal(sanitizeId("2408301234567890123"), "2408301234567890123");
    assert.equal(sanitizeId(" abc_123 "), "abc_123");
  });

  test("rejects anything that isn't a plausible id", () => {
    for (const value of ["", "  ", "a b", "a/b", "a'b", "<script>", "x".repeat(65), 5, null]) {
      assert.equal(sanitizeId(value), null);
    }
  });
});
