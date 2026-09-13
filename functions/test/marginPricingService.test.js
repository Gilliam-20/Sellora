const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const margin = require("../lib/marginPricingService");

describe("calculatePricing - target margin formula", () => {
  test("matches the worked example from the spec (20% target, 3% fee)", () => {
    const result = margin.calculatePricing({
      supplierCost: 20,
      shippingCost: 7,
      paymentFeePercentage: 0.03,
      advertisingCost: 5,
      refundAllowance: 2,
      targetNetMargin: 0.20,
    });

    // fixedCosts = 20+7+5+2 = 34; price = 34 / (1 - 0.20 - 0.03) = 44.1558..
    assert.equal(result.fixedCosts, 34);
    assert.ok(Math.abs(result.sellingPrice - 44.16) < 0.01);
    assert.ok(Math.abs(result.netMarginPercent - 0.20) < 0.005);
    assert.equal(result.isProfitable, true);
    assert.equal(result.isMarginAchievable, true);
  });

  test("15% target margin", () => {
    const result = margin.calculatePricing({
      supplierCost: 20,
      shippingCost: 7,
      paymentFeePercentage: 0.03,
      advertisingCost: 5,
      refundAllowance: 2,
      targetNetMargin: 0.15,
    });
    // 34 / (1 - 0.15 - 0.03) = 41.4634..
    assert.ok(Math.abs(result.sellingPrice - 41.47) < 0.01);
    assert.ok(Math.abs(result.netMarginPercent - 0.15) < 0.005);
  });

  test("30% (excellent) target margin", () => {
    const result = margin.calculatePricing({
      supplierCost: 20,
      shippingCost: 7,
      paymentFeePercentage: 0.03,
      advertisingCost: 5,
      refundAllowance: 2,
      targetNetMargin: 0.30,
    });
    // 34 / (1 - 0.30 - 0.03) = 50.7462..
    assert.ok(Math.abs(result.sellingPrice - 50.75) < 0.01);
    assert.ok(Math.abs(result.netMarginPercent - 0.30) < 0.005);
  });

  test("varies correctly with different supplier costs", () => {
    const cheap = margin.calculatePricing({
      supplierCost: 5, targetNetMargin: 0.20,
    });
    const expensive = margin.calculatePricing({
      supplierCost: 500, targetNetMargin: 0.20,
    });
    assert.ok(cheap.sellingPrice < expensive.sellingPrice);
    // No fee/shipping/ads/refunds: sellingPrice = cost / 0.8
    assert.ok(Math.abs(cheap.sellingPrice - 6.25) < 0.01);
    assert.ok(Math.abs(expensive.sellingPrice - 625) < 0.01);
  });

  test("varies correctly with different shipping costs", () => {
    const lowShipping = margin.calculatePricing({
      supplierCost: 20, shippingCost: 2, targetNetMargin: 0.20,
    });
    const highShipping = margin.calculatePricing({
      supplierCost: 20, shippingCost: 20, targetNetMargin: 0.20,
    });
    assert.ok(highShipping.sellingPrice > lowShipping.sellingPrice);
    const hasShippingFlag = (r) =>
      r.flags.some((f) => f.code === "SHIPPING_COST_TOO_HIGH");
    assert.ok(hasShippingFlag(highShipping));
    assert.equal(hasShippingFlag(lowShipping), false);
  });

  test("percentage payment fees are not double counted as a fixed cost", () => {
    const withoutFee = margin.calculatePricing({
      supplierCost: 20, paymentFeePercentage: 0, targetNetMargin: 0.20,
    });
    const withFee = margin.calculatePricing({
      supplierCost: 20, paymentFeePercentage: 0.03, targetNetMargin: 0.20,
    });
    // fixedCosts must be identical - the fee only affects the
    // denominator, never fixedCosts.
    assert.equal(withoutFee.fixedCosts, withFee.fixedCosts);
    assert.ok(withFee.sellingPrice > withoutFee.sellingPrice);
    // At the solved price, fee + net profit + costs must reconcile to price.
    const reconciled =
        withFee.paymentFeeAmount + withFee.netProfit + withFee.fixedCosts;
    assert.ok(Math.abs(reconciled - withFee.sellingPrice) < 0.02);
  });

  test("advertising cost increases price and fixedCosts", () => {
    const noAds = margin.calculatePricing({
      supplierCost: 20, advertisingCost: 0, targetNetMargin: 0.20,
    });
    const withAds = margin.calculatePricing({
      supplierCost: 20, advertisingCost: 15, targetNetMargin: 0.20,
    });
    assert.ok(withAds.sellingPrice > noAds.sellingPrice);
    assert.equal(withAds.fixedCosts, noAds.fixedCosts + 15);
  });

  test("refund allowance increases price and fixedCosts", () => {
    const noRefund = margin.calculatePricing({
      supplierCost: 20, refundAllowance: 0, targetNetMargin: 0.20,
    });
    const withRefund = margin.calculatePricing({
      supplierCost: 20, refundAllowance: 4, targetNetMargin: 0.20,
    });
    assert.ok(withRefund.sellingPrice > noRefund.sellingPrice);
    assert.equal(withRefund.fixedCosts, noRefund.fixedCosts + 4);
  });

  test("zero costs never produce a negative or invalid price", () => {
    const result = margin.calculatePricing({
      supplierCost: 0, shippingCost: 0, targetNetMargin: 0.20,
    });
    assert.equal(result.sellingPrice, 0);
    assert.ok(result.sellingPrice >= 0);
  });

  test("invalid costs sanitize to zero, never negative or NaN", () => {
    const result = margin.calculatePricing({
      supplierCost: -50,
      shippingCost: NaN,
      advertisingCost: undefined,
      refundAllowance: "not-a-number",
      targetNetMargin: 0.20,
    });
    assert.equal(result.sellingPrice, 0);
    assert.equal(Number.isNaN(result.sellingPrice), false);
    assert.ok(result.sellingPrice >= 0);
  });

  test("extreme shipping vs product cost is flagged, price stays valid", () => {
    const result = margin.calculatePricing({
      supplierCost: 5,
      shippingCost: 80,
      paymentFeePercentage: 0.03,
      targetNetMargin: 0.20,
    });
    assert.ok(result.sellingPrice > 0);
    assert.ok(result.flags.some((f) => f.code === "SHIPPING_COST_TOO_HIGH"));
  });

  test("an unreachable target margin is flagged and falls back safely", () => {
    const result = margin.calculatePricing({
      supplierCost: 20,
      paymentFeePercentage: 0.85,
      targetNetMargin: 0.30,
    });
    assert.equal(result.isMarginAchievable, false);
    const codes = result.flags.map((f) => f.code);
    assert.ok(codes.includes("TARGET_MARGIN_UNREACHABLE"));
    assert.ok(result.sellingPrice > 0);
    assert.ok(Number.isFinite(result.sellingPrice));
  });

  test("advertising cost beyond what the margin can absorb is flagged", () => {
    const result = margin.calculatePricing({
      supplierCost: 10,
      advertisingCost: 500,
      // a fixed/competitor price that can't cover that much ad spend:
      sellingPriceOverride: 15,
      targetNetMargin: 0.20,
    });
    const codes = result.flags.map((f) => f.code);
    assert.ok(codes.includes("ADVERTISING_UNPROFITABLE"));
    assert.equal(result.isProfitable, false);
  });

  test("margin below the 15% minimum but profitable warns, no error", () => {
    const result = margin.calculatePricing({
      supplierCost: 20,
      // barely above cost, well under any real margin:
      sellingPriceOverride: 21,
      targetNetMargin: 0.20,
    });
    const belowMin =
        result.flags.find((f) => f.code === "BELOW_MINIMUM_MARGIN");
    assert.ok(belowMin);
    assert.equal(belowMin.severity, "warning");
  });

  test("currency: KES rounds to a whole number, USD rounds to cents", () => {
    const usd = margin.calculatePricing({
      supplierCost: 33, targetNetMargin: 0.20, currency: "USD",
    });
    const kes = margin.calculatePricing({
      supplierCost: 33, targetNetMargin: 0.20, currency: "KES",
    });
    assert.equal(Number.isInteger(kes.sellingPrice), true);
    assert.equal(usd.sellingPrice, Math.ceil(usd.sellingPrice * 100) / 100);
  });

  test("rounding always rounds up, never down (never erodes margin)", () => {
    const raw = margin.calculateSellingPrice({
      supplierCost: 34, targetNetMargin: 0.20, paymentFeePercentage: 0.03,
    });
    // 34 / 0.77 = 44.1558.. -> must round UP to 44.16, not down to 44.15
    assert.equal(raw.sellingPrice, 44.16);
  });
});

describe("calculateBreakEvenPrice", () => {
  test("net profit is (approximately) zero at the break-even price", () => {
    const breakEven = margin.calculateBreakEvenPrice({
      supplierCost: 20,
      shippingCost: 7,
      paymentFeePercentage: 0.03,
      advertisingCost: 5,
      refundAllowance: 2,
    });
    const netProfit = margin.calculateNetProfit({
      sellingPrice: breakEven.sellingPrice,
      supplierCost: 20,
      shippingCost: 7,
      paymentFeePercentage: 0.03,
      advertisingCost: 5,
      refundAllowance: 2,
    });
    assert.ok(Math.abs(netProfit) < 0.05);
  });
});

describe("calculateMaxAdvertisingCost", () => {
  test("spending exactly the max keeps the target margin intact", () => {
    const sellingPrice = 50;
    const maxAd = margin.calculateMaxAdvertisingCost({
      sellingPrice,
      supplierCost: 20,
      shippingCost: 5,
      paymentFeePercentage: 0.03,
      refundAllowance: 1,
      targetNetMargin: 0.20,
    });
    const netProfit = margin.calculateNetProfit({
      sellingPrice,
      supplierCost: 20,
      shippingCost: 5,
      paymentFeePercentage: 0.03,
      advertisingCost: maxAd,
      refundAllowance: 1,
    });
    const netMarginPercent =
        margin.calculateNetMarginPercent({ sellingPrice, netProfit });
    assert.ok(Math.abs(netMarginPercent - 0.20) < 0.005);
  });

  test("never returns a negative allowance", () => {
    const maxAd = margin.calculateMaxAdvertisingCost({
      sellingPrice: 10,
      supplierCost: 50,
      targetNetMargin: 0.20,
    });
    assert.equal(maxAd, 0);
  });
});

describe("calculateProfitPerOrder", () => {
  test("scales net profit by quantity", () => {
    const result = margin.calculatePricing({
      supplierCost: 20, targetNetMargin: 0.20, quantity: 3,
    });
    assert.ok(Math.abs(result.profitPerOrder - result.netProfit * 3) < 0.01);
  });

  test("invalid quantity falls back to 1", () => {
    const profit = margin.calculateProfitPerOrder({
      netProfit: 10, quantity: -5,
    });
    assert.equal(profit, 10);
  });
});

describe("recalculatePricing", () => {
  test("recomputes fresh when supplier cost changes - no stale state", () => {
    const first = margin.calculatePricing({
      supplierCost: 20, shippingCost: 7, targetNetMargin: 0.20,
    });
    const afterCostIncrease = margin.recalculatePricing(
        { supplierCost: 20, shippingCost: 7, targetNetMargin: 0.20 },
        { supplierCost: 40 },
    );
    assert.ok(afterCostIncrease.sellingPrice > first.sellingPrice);
    assert.equal(afterCostIncrease.inputs.supplierCost, 40);
    assert.equal(afterCostIncrease.inputs.shippingCost, 7);
  });

  test("recomputes from scratch when shipping cost changes", () => {
    const first = margin.calculatePricing({
      supplierCost: 20, shippingCost: 5, targetNetMargin: 0.20,
    });
    const afterShippingIncrease = margin.recalculatePricing(
        { supplierCost: 20, shippingCost: 5, targetNetMargin: 0.20 },
        { shippingCost: 25 },
    );
    assert.ok(afterShippingIncrease.sellingPrice > first.sellingPrice);
  });
});

describe("applyVat", () => {
  test("marks a price up by the VAT fraction", () => {
    assert.equal(margin.applyVat(100, 0.20), 120);
  });

  test("0% VAT (or omitted) returns the price unchanged", () => {
    assert.equal(margin.applyVat(100, 0), 100);
    assert.equal(margin.applyVat(100), 100);
  });

  test("sanitizes a negative or invalid price to 0", () => {
    assert.equal(margin.applyVat(-50, 0.20), 0);
    assert.equal(margin.applyVat(NaN, 0.20), 0);
  });
});

describe("convertToCurrency", () => {
  test("converts a USD amount using the given fxRate", () => {
    const result =
        margin.convertToCurrency(10, { fxRate: 129, currency: "KES" });
    assert.equal(result, 1290);
  });

  test("rounds to whole units for a zero-decimal currency (KES)", () => {
    const result =
        margin.convertToCurrency(10.001, { fxRate: 129, currency: "KES" });
    assert.equal(Number.isInteger(result), true);
  });

  test("rounds to cents for a non-zero-decimal currency, rounding up", () => {
    const result =
        margin.convertToCurrency(10, { fxRate: 0.9231, currency: "EUR" });
    assert.equal(result, 9.24); // 9.231 rounds up to 9.24, never down to 9.23
  });

  test("no fxRate given is a no-op conversion", () => {
    assert.equal(margin.convertToCurrency(42), 42);
  });
});

describe("calculatePricing - VAT and currency conversion", () => {
  const baseInput = {
    supplierCost: 20,
    shippingCost: 7,
    paymentFeePercentage: 0.03,
    advertisingCost: 5,
    refundAllowance: 2,
    targetNetMargin: 0.20,
  };

  test("defaults leave the local price equal to the USD price", () => {
    const result = margin.calculatePricing(baseInput);
    assert.equal(result.vatRate, 0);
    assert.equal(result.vatAmountUsd, 0);
    assert.equal(result.sellingPriceInclVatUsd, result.sellingPrice);
    assert.equal(result.localCurrency, "USD");
    assert.equal(result.localSellingPrice, result.sellingPrice);
  });

  test("VAT marks up the price without moving net margin/profit", () => {
    const noVat = margin.calculatePricing(baseInput);
    const withVat = margin.calculatePricing({ ...baseInput, vatRate: 0.20 });

    // The core, pre-VAT math must be untouched by vatRate.
    assert.equal(withVat.sellingPrice, noVat.sellingPrice);
    assert.equal(withVat.netProfit, noVat.netProfit);
    assert.equal(withVat.netMarginPercent, noVat.netMarginPercent);

    assert.equal(withVat.vatRate, 0.20);
    const expectedInclVat = noVat.sellingPrice * 1.20;
    assert.ok(
        Math.abs(withVat.sellingPriceInclVatUsd - expectedInclVat) < 0.01);
    const expectedVatAmount =
        withVat.sellingPriceInclVatUsd - noVat.sellingPrice;
    assert.ok(Math.abs(withVat.vatAmountUsd - expectedVatAmount) < 1e-9);
  });

  test("fxRate + localCurrency convert the VAT-inclusive price", () => {
    const result = margin.calculatePricing({
      ...baseInput, vatRate: 0.20, fxRate: 0.92, localCurrency: "EUR",
    });
    assert.equal(result.localCurrency, "EUR");
    assert.equal(result.fxRate, 0.92);
    const expected =
        margin.convertToCurrency(
            result.sellingPriceInclVatUsd, { fxRate: 0.92, currency: "EUR" });
    assert.equal(result.localSellingPrice, expected);
  });

  test("localCurrency defaults to currency when not given separately", () => {
    const result = margin.calculatePricing({
      ...baseInput, currency: "KES", fxRate: 129,
    });
    assert.equal(result.localCurrency, "KES");
    assert.equal(Number.isInteger(result.localSellingPrice), true);
  });
});
