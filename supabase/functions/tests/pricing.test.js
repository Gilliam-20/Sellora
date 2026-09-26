import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  resolveTargetMargin,
  calculateProductPricing,
  retailProductPrice,
  retailShippingPrice,
} from "../_shared/pricing.js";

// A hand-built config, bypassing getPricing()'s Firestore read - these
// tests exercise the pure margin-resolution/pricing logic only.
const basePricing = {
  targetNetMargin: 0.20,
  shippingTargetNetMargin: 0.10,
  paymentFeePercentage: 0.03,
  advertisingCostUsd: 5,
  refundAllowanceUsd: 2,
  roundingIncrementUsd: 0.01,
  targetNetMarginByCategory: { "cat-electronics": 0.25 },
  targetNetMarginByProduct: { "pid-hero": 0.30 },
  regionOverrides: {
    eu: { targetNetMargin: 0.28, paymentFeePercentage: 0.045, vatRate: 0.20 },
    uk: { targetNetMargin: 0.26, paymentFeePercentage: 0.04, vatRate: 0.20 },
    kenya: { paymentFeePercentage: 0.02 },
    // "us" intentionally has no override, to test the store-default
    // fallback for a known region key with nothing configured.
  },
};

describe("resolveTargetMargin", () => {
  test("falls back to the store default with no overrides", () => {
    assert.equal(resolveTargetMargin(basePricing, {}), 0.20);
  });

  test("category override takes effect when set", () => {
    const margin =
        resolveTargetMargin(basePricing, { categoryId: "cat-electronics" });
    assert.equal(margin, 0.25);
  });

  test("product override takes precedence over category override", () => {
    const margin = resolveTargetMargin(
        basePricing, { pid: "pid-hero", categoryId: "cat-electronics" });
    assert.equal(margin, 0.30);
  });

  test("region override applies when there's no product/category match", () => {
    assert.equal(resolveTargetMargin(basePricing, { regionKey: "eu" }), 0.28);
    assert.equal(resolveTargetMargin(basePricing, { regionKey: "uk" }), 0.26);
  });

  test("category override takes precedence over region override", () => {
    const margin = resolveTargetMargin(
        basePricing, { categoryId: "cat-electronics", regionKey: "eu" });
    assert.equal(margin, 0.25);
  });

  test("product override takes precedence over region override", () => {
    const margin = resolveTargetMargin(
        basePricing, { pid: "pid-hero", regionKey: "eu" });
    assert.equal(margin, 0.30);
  });

  test("a region with no override falls back to the store default", () => {
    assert.equal(resolveTargetMargin(basePricing, { regionKey: "us" }), 0.20);
  });

  test("an unrecognized region key falls back to the store default", () => {
    assert.equal(resolveTargetMargin(basePricing, { regionKey: "mars" }), 0.20);
  });
});

describe("retailProductPrice", () => {
  test("uses the resolved margin for the given product/category", () => {
    const defaultPrice = retailProductPrice(20, basePricing, {});
    const categoryPrice =
        retailProductPrice(20, basePricing, { categoryId: "cat-electronics" });
    const productPrice =
        retailProductPrice(20, basePricing, { pid: "pid-hero" });
    // Higher target margin -> higher price for the same cost.
    assert.ok(categoryPrice > defaultPrice);
    assert.ok(productPrice > categoryPrice);
  });

  test("never returns a negative price for a zero cost", () => {
    // Even at zero supplier cost, the configured advertising/refund
    // allowances still apply, so the price recovers those, not zero.
    assert.ok(retailProductPrice(0, basePricing, {}) >= 0);
  });

  test("region override raises the price via its higher target margin", () => {
    const defaultPrice = retailProductPrice(20, basePricing, {});
    const euPrice = retailProductPrice(20, basePricing, { regionKey: "eu" });
    assert.ok(euPrice > defaultPrice);
  });

  test("currency/fxRate never change the returned USD price", () => {
    // retailProductPrice always returns the pre-VAT, pre-conversion USD
    // price - VAT/currency conversion only show up via
    // calculateProductPricing's fuller breakdown.
    const usdPrice = retailProductPrice(20, basePricing, { regionKey: "eu" });
    const withCurrency = retailProductPrice(20, basePricing, {
      regionKey: "eu", currency: "EUR", fxRate: 0.92,
    });
    assert.equal(withCurrency, usdPrice);
  });
});

describe("calculateProductPricing", () => {
  test("returns the full breakdown, including flags", () => {
    const result =
        calculateProductPricing(20, basePricing, { pid: "pid-hero" });
    assert.equal(result.inputs.targetNetMargin, 0.30);
    assert.ok(result.sellingPrice > 0);
    assert.ok(Array.isArray(result.flags));
  });

  test("region override supplies its own target margin and payment fee", () => {
    const result =
        calculateProductPricing(20, basePricing, { regionKey: "eu" });
    assert.equal(result.inputs.targetNetMargin, 0.28);
    assert.equal(result.inputs.paymentFeePercentage, 0.045);
  });

  test("VAT marks up the price without touching net margin", () => {
    const result = calculateProductPricing(20, basePricing, {
      regionKey: "eu", currency: "EUR", fxRate: 0.92,
    });
    assert.equal(result.vatRate, 0.20);
    const expectedInclVat = result.sellingPrice * 1.20;
    assert.ok(
        Math.abs(result.sellingPriceInclVatUsd - expectedInclVat) < 0.01);
    assert.ok(
        Math.abs(result.netMarginPercent - 0.28) < 0.01,
        "net margin should be measured pre-VAT");
  });

  test("localSellingPrice converts the VAT-inclusive price via fxRate", () => {
    const result = calculateProductPricing(20, basePricing, {
      regionKey: "eu", currency: "EUR", fxRate: 0.92,
    });
    assert.equal(result.localCurrency, "EUR");
    assert.equal(result.fxRate, 0.92);
    const expected =
        Math.ceil(result.sellingPriceInclVatUsd * 0.92 * 100) / 100;
    assert.ok(Math.abs(result.localSellingPrice - expected) < 0.01);
  });

  test("kenya has no VAT and rounds the local price to whole units", () => {
    const result = calculateProductPricing(20, basePricing, {
      regionKey: "kenya", currency: "KES", fxRate: 129,
    });
    assert.equal(result.vatRate, 0);
    assert.equal(result.vatAmountUsd, 0);
    assert.equal(Number.isInteger(result.localSellingPrice), true);
  });

  test("no region/currency given behaves as before (USD, no VAT)", () => {
    const result =
        calculateProductPricing(20, basePricing, { pid: "pid-hero" });
    assert.equal(result.vatRate, 0);
    assert.equal(result.sellingPriceInclVatUsd, result.sellingPrice);
    assert.equal(result.localCurrency, "USD");
    assert.equal(result.localSellingPrice, result.sellingPrice);
  });
});

describe("retailShippingPrice", () => {
  test("marks up shipping using its own margin, not product allowances", () => {
    const shippingPrice = retailShippingPrice(10, basePricing);
    // Should recover the $10 shipping cost + fee, without folding in the
    // product's advertising/refund allowances.
    assert.ok(shippingPrice > 10);
    assert.ok(shippingPrice < 20);
  });

  test("zero shipping cost yields zero retail shipping price", () => {
    assert.equal(retailShippingPrice(0, basePricing), 0);
  });

  test("region's payment fee override shifts the shipping price", () => {
    const defaultPrice = retailShippingPrice(10, basePricing);
    const euPrice = retailShippingPrice(10, basePricing, { regionKey: "eu" });
    // eu's payment fee (0.045) is higher than the store default (0.03), so
    // more of the price is needed to cover the fee.
    assert.ok(euPrice > defaultPrice);
  });

  test("currency/fxRate never change the returned USD shipping price", () => {
    const usdPrice = retailShippingPrice(10, basePricing, { regionKey: "eu" });
    const withCurrency = retailShippingPrice(10, basePricing, {
      regionKey: "eu", currency: "EUR", fxRate: 0.92,
    });
    assert.equal(withCurrency, usdPrice);
  });
});
