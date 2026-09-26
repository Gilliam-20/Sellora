import { db, must } from "./db.js";
import * as cjApi from "./cjApi.js";
import { badRequest, notFound, unprocessable } from "./errors.js";
import { getUsdToKesRate, getRate } from "./fx.js";
import { getPricing, retailShippingPrice } from "./pricing.js";
import { resolveRegion } from "./regions.js";
import { ALERTS, logAlert, logInfo, logWarning } from "./logging.js";
import { fromRow } from "./rows.js";
import { millisOf } from "./time.js";
import {
  SHIPMENT,
  buildTracking,
  extractTrackingNumber,
  nextOrderStatus,
  shouldRefreshTracking,
} from "./tracking.js";

// How many times we'll re-drive a CJ push before parking the order for a
// human. Five spread over the retry schedule comfortably outlives a CJ blip
// or a wallet top-up.
const MAX_FULFILLMENT_ATTEMPTS = 5;
// A PUSHING claim older than this is assumed orphaned (function timeout or
// crash mid-push) and may be reclaimed by a later attempt.
const PUSH_CLAIM_STALE_MS = 5 * 60 * 1000;
// Window in which a repeat attempt with the *same* method is treated as a
// double-tap rather than a deliberate retry. Switching method is allowed
// immediately - that's a real user choice.
const DUPLICATE_ATTEMPT_WINDOW_MS = 2 * 60 * 1000;

// Platform service fee: 7% of the product subtotal only - never shipping or
// tax - snapshotted onto every order so a later change to this constant
// can't retroactively change what a historical order owes its seller. See
// SELLORA_IMPLEMENTATION_PLAN.md's "Decisions on record".
const SERVICE_FEE_RATE = 0.07;

// How long an unpaid order stays payable. It carries a snapshot of CJ's
// cost and the FX rate, so it can't be paid days later at stale prices;
// past this the api refuses to start a payment and the
// expire_unpaid_orders pg_cron sweep cancels it.
const ORDER_TTL_MS = 60 * 60 * 1000;

// Why seller_order_gate refused, as the buyer hears it. Deliberately vague:
// a buyer doesn't need to know a seller's plan or standing.
const STORE_UNAVAILABLE = "This store isn't taking orders right now";

// Money columns Postgres returns as numerics; the logic below does arithmetic
// on them, so they're coerced once on read.
const NUMERIC_FIELDS = [
  "total", "totalUsd", "totalKes", "fxRate", "refundedAmount",
  "serviceFeeRate", "serviceFeeAmount", "sellerRevenue", "shippingFee",
];

const round2 = (value) => Math.round(value * 100) / 100;

/**
 * Builds an order from cart items, pricing everything from CJ's live prices
 * (never trust a client-supplied price) and the selling store's own listed
 * price (never trust a client-supplied price for that either - only the
 * storeId is taken from the client, the price is re-read from `products`).
 * Returns the client-safe view of the created order.
 * items: [{ pid, vid, quantity }]
 * storeId: the store the buyer is checking out from (CartRepository only
 * ever holds one store's items at a time, so this is the whole cart's
 * seller - a mixed-seller cart is impossible to construct client-side, and
 * this function double-checks it below by requiring every pid to resolve to
 * *this* store's own listing).
 * logisticName: optional - the buyer's chosen CJ shipping line (as shown by
 * `calculateFreight`). Only the *name* is trusted from the client; its price
 * is always re-derived from CJ's own freight quote for this address, never
 * from anything the client sends. Falls back to the cheapest option when
 * omitted or when it no longer matches an option CJ actually offers.
 */
async function createOrder({ uid, items, shippingAddress, logisticName, storeId }) {
  validateOrderRequest(items, shippingAddress, storeId);

  const store = must(await db().from("stores")
      .select("id, seller_id").eq("id", storeId).maybeSingle());
  if (!store) throw notFound("Store not found");
  const sellerId = store.seller_id;

  // Standing and plan limits are the server's to enforce: a suspended or
  // lapsed seller, or one past their plan's order_limit, can't be sold
  // through, whatever the client let them publish.
  const gate = must(await db().rpc("seller_order_gate", { p_seller_id: sellerId }));
  if (gate !== "ok") {
    logWarning("order_refused_seller_gate", { storeId, sellerId, reason: gate });
    throw unprocessable(STORE_UNAVAILABLE);
  }

  // Currency/region are derived from the shipping address server-side -
  // never trust a client-supplied currency.
  const { region: regionKey, currency } = resolveRegion(shippingAddress.countryCode);

  const pricing = await getPricing();
  const priced = await Promise.all(
      items.map(async (item) => {
        const [variant, listing, stock] = await Promise.all([
          cjApi.getVariant(item.vid),
          db().from("products")
              .select("id, title, image_url, sell_price, is_listed, variants")
              .eq("store_id", storeId).eq("id", item.pid).maybeSingle()
              .then(must),
          cjApi.getProductStock(item.pid),
        ]);
        if (variant.pid !== item.pid) {
          throw badRequest("The selected product variant does not match its product");
        }
        // getVariant passes CJ's price through unparsed, so it can be null.
        // The pricing engine sanitizes a null cost to 0 and would happily
        // solve for a 0.00 selling price - i.e. give the goods away while we
        // still pay CJ wholesale. Refuse the checkout instead.
        const supplierUnitPriceUsd = Number(variant.supplierPriceUsd);
        if (!Number.isFinite(supplierUnitPriceUsd) || supplierUnitPriceUsd <= 0) {
          throw unprocessable(
              `No usable supplier price for variant ${item.vid}; ` +
              "this product is temporarily unavailable to buy");
        }
        // Retail price is the *seller's own* listed price, not a fresh
        // platform-margin price off CJ's cost - this is what actually makes
        // sellerRevenue below mean anything. A seller who hasn't listed this
        // product in this store, or has unpublished/disabled this exact
        // variant, cannot be checked out against.
        if (!listing || listing.is_listed !== true) {
          throw unprocessable(`Product ${item.pid} is not available in this store`);
        }
        const variants = Array.isArray(listing.variants) ? listing.variants : [];
        const variantEntry = variants.find((v) => v.vid === item.vid);
        if (variants.length && (!variantEntry || variantEntry.enabled === false)) {
          throw unprocessable(`The selected variant is not available for product ${item.pid}`);
        }
        // Treated as USD, matching every other *Usd figure in this function.
        // Holds today because nothing lets a seller list a product in a
        // currency other than the ProductModel default (USD) - revisit this
        // line if a seller-side listing-currency picker ever ships.
        const retailUnitPriceUsd = Number(listing.sell_price);
        const refusal = lineRefusal({
          supplierUnitPriceUsd,
          retailUnitPriceUsd,
          quantity: item.quantity,
          available: stock?.[item.vid],
        });
        if (refusal === "below_cost") {
          logWarning("order_refused_below_cost", {
            storeId, pid: item.pid, vid: item.vid, supplierUnitPriceUsd, retailUnitPriceUsd,
          });
        }
        if (refusal) throw unprocessable(LINE_REFUSALS[refusal](item));
        return {
          pid: item.pid,
          vid: item.vid,
          quantity: item.quantity,
          name: variant.name || listing.title || "",
          sku: variant.sku,
          imageUrl: variantEntry?.image || listing.image_url || "",
          supplierUnitPriceUsd,
          retailUnitPriceUsd,
        };
      }),
  );

  for (const item of priced) {
    item.supplierLineTotalUsd = round2(item.supplierUnitPriceUsd * item.quantity);
    item.retailLineTotalUsd = round2(item.retailUnitPriceUsd * item.quantity);
  }
  const supplierSubtotalUsd = priced.reduce((sum, i) => sum + i.supplierLineTotalUsd, 0);
  const retailSubtotalUsd = priced.reduce((sum, i) => sum + i.retailLineTotalUsd, 0);
  // USD bookkeeping figures, parallel to supplierSubtotalUsd/retailSubtotalUsd
  // above - not yet wired to a real payout (that's the IntaSend Split
  // Payments sub-account work in SELLORA_IMPLEMENTATION_PLAN.md PHASE 8,
  // still gated on confirming its five API specifics against a real
  // account). This is the snapshot those payouts will eventually read.
  const { serviceFeeAmountUsd, sellerRevenueUsd } =
    splitServiceFee(retailSubtotalUsd, supplierSubtotalUsd);

  const freightOptions = await cjApi.calculateFreight({
    endCountryCode: shippingAddress.countryCode,
    products: items.map((i) => ({ vid: i.vid, quantity: i.quantity })),
  });
  if (!Array.isArray(freightOptions) || freightOptions.length === 0) {
    throw unprocessable("No shipping option is available for this address");
  }
  // An option with no usable price is not a free option - treat it as
  // ineligible so it can't win the "cheapest" comparison and make us quote
  // (and eat) shipping at zero.
  const priceOf = (option) => {
    const price = Number(option?.logisticPrice);
    return Number.isFinite(price) && price >= 0 ? price : Infinity;
  };
  let chosenLogistic;
  if (logisticName) {
    // The buyer picked a method earlier in the flow (a separate
    // `calculateFreight` call), but freight quotes can change between then
    // and now - re-match it against *this* call's options rather than
    // trusting anything else about the earlier quote.
    chosenLogistic = freightOptions.find((o) => o?.logisticName === logisticName);
    if (!chosenLogistic || !Number.isFinite(priceOf(chosenLogistic))) {
      throw unprocessable(
          "The selected shipping method is no longer available for this address");
    }
  } else {
    chosenLogistic = freightOptions.reduce((cheapest, option) =>
      priceOf(option) < priceOf(cheapest) ? option : cheapest,
    );
  }
  const freightUsd = priceOf(chosenLogistic);
  if (!Number.isFinite(freightUsd)) {
    throw unprocessable("No shipping option is available for this address");
  }

  const retailFreightUsd = retailShippingPrice(freightUsd, pricing, { regionKey });
  const totalUsd = round2(retailSubtotalUsd + retailFreightUsd);
  // Sellora's own platform take: what the buyer paid, minus CJ's actual
  // costs, minus what's owed to the seller - i.e. the service fee plus the
  // freight margin, which is Sellora's (owner decision, 2026-09-26).
  const estimatedProfitUsd = round2(
      totalUsd - supplierSubtotalUsd - freightUsd - sellerRevenueUsd);

  // Last line of defence: never write an order a customer could pay nothing
  // for, whatever combination of upstream prices produced it.
  if (!Number.isFinite(totalUsd) || totalUsd <= 0) {
    throw new Error("Order total could not be priced");
  }

  // Kept in USD->KES regardless of the shopper's region: IntaSend
  // (M-Pesa/card/Google Pay) always settles in KES.
  const fxRate = await getUsdToKesRate();
  const totalKes = Math.ceil(totalUsd * fxRate);

  // The amount/currency the shopper actually sees and pays at checkout.
  let totalAmount;
  let displayRate = 1;
  if (currency === "USD") {
    totalAmount = totalUsd;
  } else if (currency === "KES") {
    displayRate = fxRate;
    totalAmount = totalKes;
  } else {
    displayRate = await getRate("USD", currency);
    totalAmount = round2(totalUsd * displayRate);
  }
  const display = (usd) => round2(usd * displayRate);

  const id = crypto.randomUUID();
  const row = {
    id,
    // Short and human-readable for receipts and support; the id stays the
    // real key (and IntaSend's api_ref).
    code: `SLR-${id.slice(0, 8).toUpperCase()}`,
    buyer_id: uid,
    seller_id: sellerId,
    store_id: storeId,
    status: "pending",
    payment_status: "pending",
    currency,
    total: totalAmount,
    // The client-visible fee snapshot, in the order's own currency so it
    // reads against `total`. The USD originals are kept server-side below.
    service_fee_rate: SERVICE_FEE_RATE,
    service_fee_amount: display(serviceFeeAmountUsd),
    seller_revenue: display(sellerRevenueUsd),
    shipping_fee: display(retailFreightUsd),
    logistic_name: chosenLogistic?.logisticName || null,
    shipping_address: shippingAddress,
    // What the app renders: priced in `currency`, in OrderItem's shape.
    items: priced.map((item) => ({
      productId: item.pid,
      cjProductId: item.pid,
      variantId: item.vid,
      title: item.name,
      imageUrl: item.imageUrl,
      quantity: item.quantity,
      unitPrice: display(item.retailUnitPriceUsd),
    })),
    // Server-only (no client column grant).
    total_usd: totalUsd,
    total_kes: totalKes,
    fx_rate: fxRate,
    supplier_subtotal_usd: supplierSubtotalUsd,
    supplier_freight_usd: freightUsd,
    retail_subtotal_usd: retailSubtotalUsd,
    retail_freight_usd: retailFreightUsd,
    service_fee_amount_usd: serviceFeeAmountUsd,
    seller_revenue_usd: sellerRevenueUsd,
    estimated_profit_usd: estimatedProfitUsd,
    lines: priced.map((item) => ({
      productId: item.pid,
      variantId: item.vid,
      sku: item.sku,
      title: item.name,
      quantity: item.quantity,
      supplierUnitPriceUsd: item.supplierUnitPriceUsd,
      supplierLineTotalUsd: item.supplierLineTotalUsd,
      retailUnitPriceUsd: item.retailUnitPriceUsd,
      retailLineTotalUsd: item.retailLineTotalUsd,
      currency: "USD",
    })),
    fulfillment_items: priced.map(({ pid, vid, quantity }) => ({ pid, vid, quantity })),
    expires_at: new Date(Date.now() + ORDER_TTL_MS).toISOString(),
  };
  const created = must(await db().from("orders").insert(row)
      .select("created_at").single());
  return {
    ...clientView(fromRow(row)),
    createdAt: created.created_at,
  };
}

/**
 * The fields of an order a buyer may see - what createOrder answers with.
 * Deliberately a whitelist: the order row also carries the supplier cost,
 * what the seller earns (together, the seller's margin) and provider
 * references.
 * @param {object} order camelCase order.
 * @return {object} The client-safe subset, with `totalAmount`/`totalKes`
 *   named as the app reads them.
 */
function clientView(order) {
  return {
    id: order.id,
    code: order.code,
    storeId: order.storeId,
    status: order.status,
    paymentStatus: order.paymentStatus,
    currency: order.currency,
    totalAmount: order.total,
    totalKes: order.totalKes,
    shippingFee: order.shippingFee,
    logisticName: order.logisticName,
    serviceFeeRate: order.serviceFeeRate,
    serviceFeeAmount: order.serviceFeeAmount,
    expiresAt: order.expiresAt,
    items: order.items,
  };
}

/**
 * Splits a USD product subtotal into the platform's service fee and what
 * Sellora owes the seller. Under collect-and-disburse Sellora pays CJ the
 * goods cost out of the buyer's money, so the seller is owed the retail
 * subtotal less that cost and the fee. Freight is not part of either: the
 * buyer's shipping charge pays CJ's freight and the margin on it is
 * Sellora's. Pure/synchronous so it can be unit-tested without a
 * database/CJ mock - see marginPricingService.js for the same pattern.
 * @param {number} retailSubtotalUsd Sum of retail line totals, USD, excluding
 *   shipping (the fee is never charged on shipping - see SERVICE_FEE_RATE).
 * @param {number} supplierSubtotalUsd Sum of CJ's goods cost for the same
 *   lines, USD, excluding freight.
 * @return {{serviceFeeAmountUsd: number, sellerRevenueUsd: number}}
 */
function splitServiceFee(retailSubtotalUsd, supplierSubtotalUsd) {
  const positive = (value) => Number.isFinite(value) && value > 0 ? value : 0;
  const subtotal = positive(retailSubtotalUsd);
  const serviceFeeAmountUsd = round2(subtotal * SERVICE_FEE_RATE);
  const sellerRevenueUsd = round2(
      subtotal - positive(supplierSubtotalUsd) - serviceFeeAmountUsd);
  return { serviceFeeAmountUsd, sellerRevenueUsd };
}

// What the buyer is told for each lineRefusal reason.
const LINE_REFUSALS = Object.freeze({
  no_price: (item) => `Product ${item.pid} has no usable price set by its seller`,
  below_cost: (item) => `Product ${item.pid} can't be sold at its current price`,
  out_of_stock: () => "The selected variant is out of stock",
  insufficient_stock: () => "Not enough of the selected variant is in stock",
});

/**
 * Whether one checkout line may be sold, as a pure decision.
 *
 * The price floor: the seller's price, less the service fee, must cover
 * CJ's live cost of the item. Below it Sellora would pay CJ more than the
 * buyer paid for the goods and the seller's revenue would go negative.
 * Stock is checked only when CJ gave a readable count for this variant
 * (cjApi.getProductStock returns null for "unknown", never zeros).
 * @param {{supplierUnitPriceUsd: number, retailUnitPriceUsd: number,
 *   quantity: number, available: (number|undefined)}} line
 * @return {string|null} A LINE_REFUSALS key, or null when the line is fine.
 */
function lineRefusal({ supplierUnitPriceUsd, retailUnitPriceUsd, quantity, available }) {
  if (!Number.isFinite(retailUnitPriceUsd) || retailUnitPriceUsd <= 0) return "no_price";
  if (round2(retailUnitPriceUsd * (1 - SERVICE_FEE_RATE)) < supplierUnitPriceUsd) {
    return "below_cost";
  }
  if (Number.isFinite(available)) {
    if (available <= 0) return "out_of_stock";
    if (available < quantity) return "insufficient_stock";
  }
  return null;
}

/**
 * @param {object} order Order.
 * @param {number=} now Current epoch ms.
 * @return {boolean} Whether an unpaid order is past its payment window. An
 *   order from before expires_at existed never expires.
 */
function isExpired(order, now = Date.now()) {
  return Boolean(order.expiresAt) && millisOf(order.expiresAt) <= now;
}

function validateOrderRequest(items, shippingAddress, storeId) {
  if (typeof storeId !== "string" || !storeId) {
    throw badRequest("storeId is required");
  }
  if (!Array.isArray(items) || items.length === 0 || items.length > 50) {
    throw badRequest("items[] must contain between 1 and 50 items");
  }
  if (!shippingAddress || typeof shippingAddress.countryCode !== "string" || shippingAddress.countryCode.length !== 2) {
    throw badRequest("A valid two-letter shippingAddress.countryCode is required");
  }
  const variants = new Set();
  for (const item of items) {
    if (!item || typeof item.pid !== "string" || !item.pid || typeof item.vid !== "string" || !item.vid) {
      throw badRequest("Each item requires pid and vid");
    }
    if (!Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 20) {
      throw badRequest("Each item quantity must be an integer between 1 and 20");
    }
    if (variants.has(item.vid)) throw badRequest("Duplicate variants must be combined before checkout");
    variants.add(item.vid);
  }
}

/**
 * @param {object} row An `orders` row.
 * @return {object} The camelCase order the logic below works on, with
 *   numerics coerced and the Firestore-era aliases (`uid`, `totalAmount`)
 *   the payment handlers and refund rules read.
 */
function orderFromRow(row) {
  const order = fromRow(row);
  for (const field of NUMERIC_FIELDS) {
    if (order[field] != null) order[field] = Number(order[field]);
  }
  order.uid = order.buyerId;
  order.totalAmount = order.total;
  return order;
}

async function getOrder(orderId) {
  const row = must(await db().from("orders").select("*").eq("id", orderId).maybeSingle());
  if (!row) throw notFound("Order not found");
  return orderFromRow(row);
}

/**
 * Records a payment attempt (see the `attach_order_payment_attempt` SQL
 * function): the latest one on `paymentRef`, and every one on
 * `paymentAttempts`, so a late webhook for an earlier attempt still matches.
 * @return {Promise<boolean>} False when the order was paid (or refunded) in
 *   the meantime and nothing was written.
 */
async function attachPaymentAttempt(orderId, { paymentMethod, paymentProvider, paymentRef }) {
  return must(await db().rpc("attach_order_payment_attempt", {
    p_order_id: orderId,
    p_method: paymentMethod,
    p_provider: paymentProvider,
    p_ref: paymentRef,
  }));
}

/**
 * Whether `ref` identifies a payment attempt this order actually started -
 * checked against the full attempt history, not just the latest `paymentRef`,
 * so switching payment method doesn't orphan the earlier attempt.
 * @param {object} order Order.
 * @param {{invoiceId: (string|undefined), checkoutId: (string|undefined)}} ref
 *   Provider reference taken from an untrusted source (e.g. a webhook body).
 * @return {boolean} True if this order started that attempt.
 */
function paymentRefMatches(order, { invoiceId, checkoutId }) {
  if (!invoiceId && !checkoutId) return false;
  const refs = [
    order.paymentRef,
    ...(Array.isArray(order.paymentAttempts) ?
      order.paymentAttempts.map((a) => a && a.paymentRef) : []),
  ];
  return refs.some((r) =>
    r && ((invoiceId && r.invoiceId === invoiceId) ||
          (checkoutId && r.checkoutId === checkoutId)));
}

/**
 * Whether the order already has an in-flight attempt with this same method,
 * started recently enough that a second one is almost certainly a double-tap
 * rather than a deliberate retry. Switching to a different method is always
 * allowed - that's a real user choice, and the history records both.
 * @param {object} order Order.
 * @param {string} paymentMethod The method about to be started.
 * @param {number=} now Current epoch ms.
 * @return {boolean} True if a duplicate attempt should be refused.
 */
function hasPendingAttempt(order, paymentMethod, now = Date.now()) {
  if (order.paymentStatus !== "awaiting_confirmation") return false;
  if (order.paymentMethod !== paymentMethod) return false;
  return now - millisOf(order.lastPaymentAttemptAt) < DUPLICATE_ATTEMPT_WINDOW_MS;
}

/**
 * The fulfillment state machine, as a pure decision: given an order's current
 * CJ push state, may this invocation send it to CJ?
 *
 * `PUSHED` and `NEEDS_RECONCILIATION` are terminal, a `PUSHING` claim blocks
 * the loser of a webhook/poll race until it goes stale (its holder timed out
 * or crashed), `FAILED` is retryable, and an order that has used up its
 * attempt budget parks for a human instead of being retried forever.
 * @param {object} order Order.
 * @param {number=} now Current epoch ms.
 * @return {{proceed: boolean, reason: string, fulfilled: boolean,
 *   attempts: (number|undefined), park: (boolean|undefined)}} What the caller
 *   should do: `proceed` claims the push, `park` writes it off for a human.
 */
function decidePushClaim(order, now = Date.now()) {
  if (order.cjOrderStatus === "PUSHED") {
    return { proceed: false, reason: "already_pushed", fulfilled: true };
  }
  if (order.cjOrderStatus === "NEEDS_RECONCILIATION") {
    return { proceed: false, reason: "needs_reconciliation", fulfilled: false };
  }
  // A live claim from a concurrent invocation. Only reclaim it once it's
  // gone stale, which means the holder timed out or crashed mid-push -
  // otherwise this is the loser of a webhook/poll race and must not send
  // CJ a second, duplicate order.
  if (order.cjOrderStatus === "PUSHING") {
    if (now - millisOf(order.cjPushClaimedAt) < PUSH_CLAIM_STALE_MS) {
      return { proceed: false, reason: "push_in_progress", fulfilled: false };
    }
  }

  const attempts = (order.cjPushAttempts || 0) + 1;
  if (attempts > MAX_FULFILLMENT_ATTEMPTS) {
    return {
      proceed: false,
      reason: "attempts_exhausted",
      fulfilled: false,
      park: true,
      attempts,
    };
  }
  return { proceed: true, reason: "claimed", fulfilled: false, attempts };
}

/**
 * Marks an order paid and pushes it to CJ for fulfillment. Idempotent - safe
 * to call multiple times for the same order (e.g. from both a webhook and a
 * client-triggered poll racing each other).
 *
 * The claim is a compare-and-set: the UPDATE only lands if the row still
 * has the CJ state (`cj_order_status`, `cj_push_attempts`) this invocation
 * decided from. Every claim bumps the attempt count, so of two racers
 * exactly one matches and the other sees zero rows - the Postgres
 * equivalent of the Firestore transaction this replaced.
 *
 * The payment and the push are deliberately separated: once this returns the
 * customer's money is taken and `paymentStatus` is "paid" regardless of what
 * CJ did. A CJ failure is *our* problem to retry (see
 * `retryFailedFulfillments`), never a "payment failed" shown to a customer
 * who has in fact paid - so a push failure resolves to a return value here
 * rather than a thrown error.
 * @param {string} orderId Order id.
 * @return {Promise<object>} `{ paid, fulfilled, cjOrderStatus, ... }`.
 */
async function fulfillOrder(orderId) {
  const order = await getOrder(orderId);

  // A confirmation arriving after a refund (a slow webhook retry) must not
  // flip the order back to paid or ship goods that were refunded.
  if (order.paymentStatus === "refunded" || order.paymentStatus === "partially_refunded") {
    return { paid: true, fulfilled: false, alreadyHandled: true, reason: "refunded" };
  }

  // Paid after it was cancelled - it expired, or an admin cancelled it,
  // while a payment was still in flight. The money is taken but nothing
  // should ship: record the payment and park the order for a refund.
  if (order.status === "cancelled") {
    const parked = must(await db().from("orders").update({
      payment_status: "paid",
      cj_order_status: "NEEDS_RECONCILIATION",
      updated_at: new Date().toISOString(),
    })
        .eq("id", orderId)
        .in("payment_status", ["pending", "awaiting_confirmation", "failed"])
        .select("id"));
    if (parked.length > 0) {
      logAlert(ALERTS.ORDER_NEEDS_RECONCILIATION, {
        orderId,
        uid: order.uid,
        reason: "paid_after_cancel",
      });
    }
    return {
      paid: true,
      fulfilled: false,
      alreadyHandled: parked.length === 0,
      reason: "cancelled",
    };
  }

  const claim = decidePushClaim(order);
  if (claim.park || claim.proceed) {
    const now = new Date().toISOString();
    const update = claim.park ?
      { payment_status: "paid", cj_order_status: "NEEDS_RECONCILIATION", updated_at: now } :
      {
        payment_status: "paid",
        cj_order_status: "PUSHING",
        cj_push_attempts: claim.attempts,
        cj_push_claimed_at: now,
        updated_at: now,
      };
    // Fulfilment starts now; never walk back a status a seller or the
    // tracking refresh has already moved on.
    if (order.status === "pending") update.status = "processing";
    const won = must(await db().from("orders").update(update)
        .eq("id", orderId)
        .eq("cj_order_status", order.cjOrderStatus)
        .eq("cj_push_attempts", order.cjPushAttempts || 0)
        .select("id"));
    if (won.length === 0) {
      // Another invocation changed the CJ state between our read and our
      // write - it holds the claim now.
      return { paid: true, fulfilled: false, alreadyHandled: true, reason: "push_in_progress" };
    }
  }

  if (claim.park) {
    logAlert(ALERTS.ORDER_NEEDS_RECONCILIATION, {
      orderId,
      reason: "attempts_exhausted",
      attempts: claim.attempts,
    });
  }

  if (!claim.proceed) {
    return {
      paid: true,
      fulfilled: claim.fulfilled,
      alreadyHandled: true,
      reason: claim.reason,
    };
  }

  try {
    const cjResult = await cjApi.createDropshipOrder({
      orderNumber: orderId,
      shippingAddress: order.shippingAddress,
      logisticName: order.logisticName,
      remark: `Sellora order ${order.code || orderId}`,
      products: (order.fulfillmentItems || []).map((i) => ({
        vid: i.vid,
        quantity: i.quantity,
        storeLineItemId: `${orderId}-${i.vid}`,
      })),
    });
    must(await db().from("orders").update({
      cj_order_status: "PUSHED",
      cj_order_id: cjResult?.orderId || cjResult?.id || null,
      cj_order_number: cjResult?.orderNum || null,
      updated_at: new Date().toISOString(),
    }).eq("id", orderId));
    return { paid: true, fulfilled: true, alreadyHandled: false, cjResult };
  } catch (err) {
    // Keep the order marked PAID (the customer *was* charged) and record the
    // failure so `retryFailedFulfillments` can re-drive it. Only once the
    // attempt budget is spent does it park for a human - the most likely
    // cause here is an empty CJ wallet, which fails every order until it's
    // topped up and then wants them all re-pushed.
    const exhausted = claim.attempts >= MAX_FULFILLMENT_ATTEMPTS;
    logAlert(ALERTS.CJ_PUSH_FAILED, {
      orderId,
      uid: order.uid,
      attempt: claim.attempts,
      maxAttempts: MAX_FULFILLMENT_ATTEMPTS,
      outcome: exhausted ? "parked" : "will_retry",
    }, err);
    if (exhausted) {
      logAlert(ALERTS.ORDER_NEEDS_RECONCILIATION, {
        orderId,
        uid: order.uid,
        reason: "cj_push_failed",
        attempts: claim.attempts,
      }, err);
    }
    const now = new Date().toISOString();
    must(await db().from("orders").update({
      cj_order_status: exhausted ? "NEEDS_RECONCILIATION" : "FAILED",
      cj_order_error: String(err.message || err).slice(0, 1000),
      cj_last_failed_at: now,
      updated_at: now,
    }).eq("id", orderId));
    return {
      paid: true,
      fulfilled: false,
      alreadyHandled: false,
      cjOrderStatus: exhausted ? "NEEDS_RECONCILIATION" : "FAILED",
    };
  }
}

/**
 * Re-drives orders that were paid but whose CJ push failed, plus any order
 * left holding a stale PUSHING claim by a timed-out invocation. Without this
 * a CJ outage or an empty CJ wallet leaves every order of that period paid
 * and permanently unfulfilled, since the customer stops polling as soon as
 * they're told the payment succeeded.
 * @param {number=} limit Maximum orders to re-drive in one run.
 * @return {Promise<object>} Counts for logging.
 */
async function retryFailedFulfillments(limit = 20) {
  const stuck = must(await db().from("orders")
      .select("id, cj_order_status, cj_push_claimed_at")
      .eq("payment_status", "paid")
      .in("cj_order_status", ["FAILED", "PUSHING"])
      .limit(limit));

  let retried = 0;
  let recovered = 0;
  for (const row of stuck) {
    // fulfillOrder refuses a PUSHING claim that's still live, so skipping
    // those here just avoids a pointless round trip.
    if (row.cj_order_status === "PUSHING" &&
        Date.now() - millisOf(row.cj_push_claimed_at) < PUSH_CLAIM_STALE_MS) {
      continue;
    }
    retried++;
    const result = await fulfillOrder(row.id);
    if (result.fulfilled) recovered++;
  }
  if (retried > 0) {
    logInfo("fulfillment_retry_run", {
      scanned: stuck.length,
      retried,
      recovered,
    });
  }
  return { scanned: stuck.length, retried, recovered };
}

/**
 * Asks CJ where an order actually is and writes the answer onto the order,
 * which is what the app's tracking screen reads.
 *
 * Rationed rather than unconditional: a parcel's status changes a handful of
 * times over several days, so re-asking on every screen open would spend the
 * CJ rate limit to re-learn the same thing. `force` (a customer pulling to
 * refresh) narrows the window rather than removing it.
 * @param {string} orderId Order id.
 * @param {{force: (boolean|undefined)}=} opts `force` for a user-initiated
 *   refresh.
 * @return {Promise<{refreshed: boolean, reason: string,
 *   tracking: (object|null)}>} The current snapshot either way.
 */
async function refreshOrderTracking(orderId, { force = false } = {}) {
  const order = await getOrder(orderId);
  const decision = shouldRefreshTracking(order, { force });
  if (!decision.refresh) {
    return {
      refreshed: false,
      reason: decision.reason,
      tracking: order.tracking || null,
    };
  }

  let cjOrder;
  try {
    cjOrder = await cjApi.getOrderDetail(order.cjOrderId);
  } catch (err) {
    // A tracking lookup failing is not the customer's problem and not worth
    // an alert - the next scheduled pass tries again, and the screen keeps
    // showing the last known state.
    logWarning("tracking_lookup_failed", {
      orderId,
      cjOrderId: order.cjOrderId,
    }, err);
    return {
      refreshed: false,
      reason: "lookup_failed",
      tracking: order.tracking || null,
    };
  }

  const trackingNumber = extractTrackingNumber(cjOrder);
  const events = trackingNumber ? await cjApi.getTrackInfo(trackingNumber) : [];
  const tracking = buildTracking({ cjOrder, events });

  const now = new Date().toISOString();
  const update = {
    tracking,
    tracking_complete: tracking.complete,
    tracking_checked_at: now,
    updated_at: now,
  };
  // The app's OrderModel reads the number from its own column.
  if (tracking.trackingNumber) update.tracking_number = tracking.trackingNumber;
  const status = nextOrderStatus(order.status, tracking.orderStatus);
  if (status) update.status = status;
  must(await db().from("orders").update(update).eq("id", orderId));

  const previous = order.tracking?.status;
  if (tracking.status !== previous) {
    logInfo("tracking_status_changed", {
      orderId,
      uid: order.uid,
      from: previous || "NONE",
      to: tracking.status,
      trackingNumber: tracking.trackingNumber,
    });
    // Only the transition alerts. A parcel can sit in an exception state for
    // days, and re-alerting on every poll would train whoever watches these
    // to ignore them.
    if (tracking.status === SHIPMENT.EXCEPTION) {
      logAlert(ALERTS.DELIVERY_EXCEPTION, {
        orderId,
        uid: order.uid,
        trackingNumber: tracking.trackingNumber,
        carrier: tracking.carrier,
        detail: tracking.events[0]?.description,
      });
    }
  }
  return {
    refreshed: true,
    reason: "updated",
    tracking,
    status: status || order.status,
  };
}

/**
 * Polls CJ for every order still in flight. This is what makes tracking
 * arrive on its own - without it an order only ever updates when its
 * customer happens to open the tracking screen.
 * @param {number=} limit Maximum orders to refresh in one run.
 * @return {Promise<object>} Counts for logging.
 */
async function refreshTrackingBatch(limit = 25) {
  // Oldest-checked first (never-checked before everything), so a run that
  // hits the limit resumes where the previous one stopped instead of
  // re-polling the same orders forever.
  const inFlight = must(await db().from("orders")
      .select("id")
      .eq("cj_order_status", "PUSHED")
      .eq("tracking_complete", false)
      .order("tracking_checked_at", { ascending: true, nullsFirst: true })
      .limit(limit));

  let refreshed = 0;
  let delivered = 0;
  for (const row of inFlight) {
    const result = await refreshOrderTracking(row.id);
    if (!result.refreshed) continue;
    refreshed++;
    if (result.tracking?.status === SHIPMENT.DELIVERED) delivered++;
  }
  if (refreshed > 0) {
    logInfo("tracking_refresh_run", {
      scanned: inFlight.length,
      refreshed,
      delivered,
    });
  }
  return { scanned: inFlight.length, refreshed, delivered };
}

export {
  createOrder,
  clientView,
  getOrder,
  orderFromRow,
  attachPaymentAttempt,
  refreshOrderTracking,
  refreshTrackingBatch,
  fulfillOrder,
  retryFailedFulfillments,
  paymentRefMatches,
  hasPendingAttempt,
  decidePushClaim,
  MAX_FULFILLMENT_ATTEMPTS,
  PUSH_CLAIM_STALE_MS,
  DUPLICATE_ATTEMPT_WINDOW_MS,
  SERVICE_FEE_RATE,
  ORDER_TTL_MS,
  splitServiceFee,
  lineRefusal,
  isExpired,
  validateOrderRequest,
};
