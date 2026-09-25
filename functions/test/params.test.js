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
  validateFreightRequest,
  isValidMpesaPhone,
  isAllowedRedirectUrl,
  MAX_FREIGHT_LINES,
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

describe("validateFreightRequest", () => {
  const line = { vid: "V1", quantity: 2 };

  test("normalizes a valid request and drops unknown line fields", () => {
    const { value } = validateFreightRequest({
      endCountryCode: "ke",
      products: [{ ...line, price: 0 }],
    });
    assert.deepEqual(value, {
      endCountryCode: "KE",
      startCountryCode: undefined,
      products: [{ vid: "V1", quantity: 2 }],
    });
  });

  test("refuses the unbounded products[] that used to go straight to CJ", () => {
    const products = Array.from({ length: MAX_FREIGHT_LINES + 1 }, () => line);
    assert.ok(validateFreightRequest({ endCountryCode: "KE", products }).error);
  });

  test("refuses malformed countries, ids and quantities", () => {
    for (const body of [
      { endCountryCode: "Kenya", products: [line] },
      { endCountryCode: "KE", startCountryCode: "CHN", products: [line] },
      { endCountryCode: "KE", products: [] },
      { endCountryCode: "KE", products: [{ vid: "a/b", quantity: 1 }] },
      { endCountryCode: "KE", products: [{ vid: "V1", quantity: 0 }] },
      { endCountryCode: "KE", products: [{ vid: "V1", quantity: 1.5 }] },
      { endCountryCode: "KE", products: [{ vid: "V1", quantity: 21 }] },
      null,
    ]) {
      assert.ok(validateFreightRequest(body).error, JSON.stringify(body));
    }
  });
});

describe("isValidMpesaPhone", () => {
  test("accepts the 2547/2541 forms the app normalizes to", () => {
    assert.equal(isValidMpesaPhone("254712345678"), true);
    assert.equal(isValidMpesaPhone("254112345678"), true);
  });

  test("refuses anything else", () => {
    for (const value of ["0712345678", "+254712345678", "25471234567", "254812345678", 254712345678, null]) {
      assert.equal(isValidMpesaPhone(value), false, String(value));
    }
  });
});

describe("isAllowedRedirectUrl", () => {
  const origins = ["https://sellora-20.web.app"];

  test("accepts our own origin, including the hash-routed storefront path", () => {
    assert.equal(
        isAllowedRedirectUrl("https://sellora-20.web.app/#/s/amina", { origins, allowLocalhost: false }),
        true,
    );
  });

  test("refuses other sites, look-alikes, plain http and credentials", () => {
    for (const value of [
      "https://evil.example/#/s/amina",
      "https://sellora-20.web.app.evil.example/",
      "http://sellora-20.web.app/",
      "https://user:pass@sellora-20.web.app/",
      "javascript:alert(1)",
      "not a url",
      42,
    ]) {
      assert.equal(isAllowedRedirectUrl(value, { origins, allowLocalhost: false }), false, String(value));
    }
  });

  test("allows localhost only when asked (the emulator default)", () => {
    const url = "http://localhost:5000/#/s/amina";
    assert.equal(isAllowedRedirectUrl(url, { origins, allowLocalhost: false }), false);
    assert.equal(isAllowedRedirectUrl(url, { origins, allowLocalhost: true }), true);
  });
});
