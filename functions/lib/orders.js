const { db, admin } = require("./firebaseAdmin");
const cjApi = require("./cjApi");
const { badRequest, notFound, unprocessable } = require("./errors");
const { getUsdToKesRate, getRate } = require("./fx");
const { getPricing, retailProductPrice, retailShippingPrice } = require("./pricing");
const { resolveRegion } = require("./regions");
const { ALERTS, logAlert, logInfo, logWarning } = require("./logging");
const {
  SHIPMENT,
  buildTracking,
  extractTrackingNumber,
  nextOrderStatus,
  shouldRefreshTracking,
} = require("./tracking");

const ORDERS = db.collection("orders");

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

/**
 * Builds an order from cart items, pricing everything from CJ's live prices
 * (never trust a client-supplied price). Returns the created order doc.
 * items: [{ pid, vid, quantity }]
 * logisticName: optional - the buyer's chosen CJ shipping line (as shown by
 * `calculateFreight`). Only the *name* is trusted from the client; its price
 * is always re-derived from CJ's own freight quote for this address, never
 * from anything the client sends. Falls back to the cheapest option when
 * omitted or when it no longer matches an option CJ actually offers.
 */
async function createOrder({ uid, items, shippingAddress, logisticName }) {
  validateOrderRequest(items, shippingAddress);
  if (!shippingAddress?.countryCode) {
    throw badRequest("shippingAddress.countryCode is required");
  }

  // Currency/region are derived from the shipping address server-side -
  // never trust a client-supplied currency.
  const { region: regionKey, currency } = resolveRegion(shippingAddress.countryCode);

  const pricing = await getPricing();
  const priced = await Promise.all(
      items.map(async (item) => {
        const variant = await cjApi.getVariant(item.vid);
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
        const retailUnitPriceUsd = retailProductPrice(
            supplierUnitPriceUsd, pricing, { pid: item.pid, regionKey });
        if (!Number.isFinite(retailUnitPriceUsd) || retailUnitPriceUsd <= 0) {
          throw new Error(`Could not price variant ${item.vid}`);
        }
        return {
          pid: item.pid,
          vid: item.vid,
          quantity: item.quantity,
          name: variant.name,
          sku: variant.sku,
          supplierUnitPriceUsd,
          retailUnitPriceUsd,
        };
      }),
  );

  for (const item of priced) {
    item.supplierLineTotalUsd = Math.round(item.supplierUnitPriceUsd * item.quantity * 100) / 100;
    item.retailLineTotalUsd = Math.round(item.retailUnitPriceUsd * item.quantity * 100) / 100;
  }
  const supplierSubtotalUsd = priced.reduce((sum, i) => sum + i.supplierLineTotalUsd, 0);
  const retailSubtotalUsd = priced.reduce((sum, i) => sum + i.retailLineTotalUsd, 0);

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
  const totalUsd = Math.round((retailSubtotalUsd + retailFreightUsd) * 100) / 100;
  const estimatedProfitUsd = Math.round((totalUsd - supplierSubtotalUsd - freightUsd) * 100) / 100;

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
    totalAmount = Math.round(totalUsd * displayRate * 100) / 100;
  }

  const orderRef = ORDERS.doc();
  const order = {
    // userId is the canonical query field. uid remains temporarily for legacy
    // clients and can be removed after the data migration.
    userId: uid,
    uid,
    status: "pendingPayment",
    itemCount: priced.length,
    supplierSubtotalUsd,
    supplierFreightUsd: freightUsd,
    retailSubtotalUsd,
    retailFreightUsd,
    totalUsd,
    estimatedProfitUsd,
    fxRate,
    totalKes,
    currency,
    totalAmount,
    logisticName: chosenLogistic?.logisticName || null,
    shippingAddress,
    paymentMethod: null,
    paymentProvider: null,
    paymentRef: null,
    paymentStatus: "pending",
    cjOrderStatus: "NOT_PUSHED",
    cjOrderId: null,
    cjOrderNumber: null,
    // Post-purchase tracking. Written explicitly (rather than left absent
    // until the first refresh) because `refreshTrackingBatch` orders by
    // `trackingCheckedAt`, and Firestore excludes documents that don't carry
    // the field being ordered on - an order missing it would never be polled.
    //
    // `trackingComplete` mirrors `tracking.complete` at the top level so the
    // batch can filter on it: the `tracking` map itself is excluded from
    // indexing in firestore.indexes.json, since its carrier scan history
    // would otherwise be indexed field by field for nothing.
    tracking: null,
    trackingCheckedAt: null,
    trackingComplete: false,
    refundedAmount: 0,
    refunds: [],
    fulfillmentItems: priced.map(({ pid, vid, quantity }) => ({ pid, vid, quantity })),
    // Mirrored onto the order doc (as well as the items subcollection) so the
    // app can render order lines and receipts from the single document it
    // already reads, without a second query per order. Priced in `currency`
    // to match totalAmount - the subcollection keeps the USD figures.
    items: priced.map((item) => ({
      productId: item.pid,
      variantId: item.vid,
      title: item.name,
      quantity: item.quantity,
      unitPrice: Math.round(item.retailUnitPriceUsd * displayRate * 100) / 100,
    })),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  const batch = db.batch();
  batch.set(orderRef, order);
  for (const item of priced) {
    batch.set(orderRef.collection("items").doc(`${item.pid}_${item.vid}`), {
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
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  return { id: orderRef.id, ...order };
}

function validateOrderRequest(items, shippingAddress) {
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

async function getOrder(orderId) {
  const snap = await ORDERS.doc(orderId).get();
  if (!snap.exists) throw notFound("Order not found");
  return { id: snap.id, ...snap.data() };
}

async function attachPaymentAttempt(orderId, { paymentMethod, paymentProvider, paymentRef }) {
  await ORDERS.doc(orderId).update({
    paymentMethod,
    paymentProvider,
    paymentRef,
    paymentStatus: "AWAITING_CONFIRMATION",
    // paymentRef only ever holds the latest attempt. Keeping the full history
    // is what makes a duplicate charge reconcilable (two live STK prompts, or
    // a first method completing after the customer switched to a second), and
    // it's what `paymentRefMatches` checks so a late webhook for an earlier
    // attempt is still honoured. arrayUnion can't hold a server timestamp
    // sentinel, so this uses a client-side Date.
    paymentAttempts: admin.firestore.FieldValue.arrayUnion({
      paymentMethod,
      paymentProvider,
      paymentRef,
      createdAt: new Date(),
    }),
    lastPaymentAttemptAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/**
 * Whether `ref` identifies a payment attempt this order actually started -
 * checked against the full attempt history, not just the latest `paymentRef`,
 * so switching payment method doesn't orphan the earlier attempt.
 * @param {object} order Order document.
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
 * @param {object} order Order document.
 * @param {string} paymentMethod The method about to be started.
 * @return {boolean} True if a duplicate attempt should be refused.
 */
function hasPendingAttempt(order, paymentMethod) {
  if (order.paymentStatus !== "AWAITING_CONFIRMATION") return false;
  if (order.paymentMethod !== paymentMethod) return false;
  // An order awaiting confirmation from before this field existed has no
  // timestamp. Treating that as in-flight would deadlock it - the field is
  // only ever set by a new attempt, which we'd be blocking - so it falls
  // through to allowed, exactly as it behaved before the guard existed.
  const startedAt = order.lastPaymentAttemptAt?.toMillis?.() ?? 0;
  return Date.now() - startedAt < DUPLICATE_ATTEMPT_WINDOW_MS;
}

/**
 * The fulfillment state machine, as a pure decision: given an order's current
 * CJ push state, may this invocation send it to CJ?
 *
 * `PUSHED` and `NEEDS_RECONCILIATION` are terminal, a `PUSHING` claim blocks
 * the loser of a webhook/poll race until it goes stale (its holder timed out
 * or crashed), `FAILED` is retryable, and an order that has used up its
 * attempt budget parks for a human instead of being retried forever.
 * @param {object} order Order document.
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
    const claimedAt = order.cjPushClaimedAt?.toMillis?.() ?? 0;
    if (now - claimedAt < PUSH_CLAIM_STALE_MS) {
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
 * The payment and the push are deliberately separated: once this returns the
 * customer's money is taken and `paymentStatus` is "paid" regardless of what
 * CJ did. A CJ failure is *our* problem to retry (see
 * `retryFailedFulfillments`), never a "payment failed" shown to a customer
 * who has in fact paid - so a push failure resolves to a return value here
 * rather than a thrown error.
 * @param {string} orderId Order document id.
 * @return {Promise<object>} `{ paid, fulfilled, cjOrderStatus, ... }`.
 */
async function fulfillOrder(orderId) {
  const orderRef = ORDERS.doc(orderId);

  const claim = await db.runTransaction(async (tx) => {
    const snap = await tx.get(orderRef);
    if (!snap.exists) throw new Error("Order not found");
    const decision = decidePushClaim(snap.data());

    if (decision.park) {
      tx.update(orderRef, {
        paymentStatus: "paid",
        status: "paid",
        cjOrderStatus: "NEEDS_RECONCILIATION",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else if (decision.proceed) {
      tx.update(orderRef, {
        paymentStatus: "paid",
        status: "paid",
        cjOrderStatus: "PUSHING",
        cjPushAttempts: decision.attempts,
        cjPushClaimedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    return decision;
  });

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

  const order = await getOrder(orderId);

  try {
    const cjResult = await cjApi.createDropshipOrder({
      orderNumber: orderId,
      shippingAddress: order.shippingAddress,
      logisticName: order.logisticName,
      remark: `Sellora order ${orderId}`,
      products: order.fulfillmentItems.map((i) => ({
        vid: i.vid,
        quantity: i.quantity,
        storeLineItemId: `${orderId}-${i.vid}`,
      })),
    });
    await orderRef.update({
      cjOrderStatus: "PUSHED",
      cjOrderId: cjResult.orderId || cjResult.id || null,
      cjOrderNumber: cjResult.orderNum || null,
      // Seeded here as well as at creation so an order written before these
      // fields existed still matches `refreshTrackingBatch`'s query, which
      // can only see documents that carry them.
      trackingCheckedAt: order.trackingCheckedAt ?? null,
      trackingComplete: order.trackingComplete ?? false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
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
    await orderRef.update({
      cjOrderStatus: exhausted ? "NEEDS_RECONCILIATION" : "FAILED",
      cjOrderError: err.message,
      cjLastFailedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
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
  const stuck = await ORDERS
      .where("paymentStatus", "==", "paid")
      .where("cjOrderStatus", "in", ["FAILED", "PUSHING"])
      .limit(limit)
      .get();

  let retried = 0;
  let recovered = 0;
  for (const doc of stuck.docs) {
    const order = doc.data();
    // fulfillOrder refuses a PUSHING claim that's still live, so skipping
    // those here just avoids a pointless transaction.
    if (order.cjOrderStatus === "PUSHING") {
      const claimedAt = order.cjPushClaimedAt?.toMillis?.() ?? 0;
      if (Date.now() - claimedAt < PUSH_CLAIM_STALE_MS) continue;
    }
    retried++;
    const result = await fulfillOrder(doc.id);
    if (result.fulfilled) recovered++;
  }
  if (retried > 0) {
    logInfo("fulfillment_retry_run", {
      scanned: stuck.size,
      retried,
      recovered,
    });
  }
  return { scanned: stuck.size, retried, recovered };
}

/**
 * Records a provider reference discovered after payment - today the PayPal
 * capture id, which is not known until the capture succeeds and is the only
 * handle PayPal accepts for a refund. Merged into `paymentRef` rather than
 * replacing it, so the invoice/checkout/order ids stay put.
 * @param {string} orderId Order document id.
 * @param {object} ref Fields to merge into `paymentRef`.
 * @return {Promise<void>} Resolves once written.
 */
async function recordPaymentReference(orderId, ref) {
  const update = { updatedAt: admin.firestore.FieldValue.serverTimestamp() };
  let wrote = false;
  for (const [key, value] of Object.entries(ref || {})) {
    if (value == null || value === "") continue;
    update[`paymentRef.${key}`] = value;
    wrote = true;
  }
  if (!wrote) return;
  await ORDERS.doc(orderId).update(update);
}

/**
 * Asks CJ where an order actually is and writes the answer onto the order,
 * which is what the app's tracking screen reads.
 *
 * Rationed rather than unconditional: a parcel's status changes a handful of
 * times over several days, so re-asking on every screen open would spend the
 * CJ rate limit to re-learn the same thing. `force` (a customer pulling to
 * refresh) narrows the window rather than removing it.
 * @param {string} orderId Order document id.
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

  const update = {
    tracking,
    trackingComplete: tracking.complete,
    trackingCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  const status = nextOrderStatus(order.status, tracking.orderStatus);
  if (status) update.status = status;
  await ORDERS.doc(orderId).update(update);

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
  // Oldest-checked first, so a run that hits the limit resumes where the
  // previous one stopped instead of re-polling the same orders forever.
  const inFlight = await ORDERS
      .where("cjOrderStatus", "==", "PUSHED")
      .where("trackingComplete", "==", false)
      .orderBy("trackingCheckedAt", "asc")
      .limit(limit)
      .get();

  let refreshed = 0;
  let delivered = 0;
  for (const doc of inFlight.docs) {
    const result = await refreshOrderTracking(doc.id);
    if (!result.refreshed) continue;
    refreshed++;
    if (result.tracking?.status === SHIPMENT.DELIVERED) delivered++;
  }
  if (refreshed > 0) {
    logInfo("tracking_refresh_run", {
      scanned: inFlight.size,
      refreshed,
      delivered,
    });
  }
  return { scanned: inFlight.size, refreshed, delivered };
}

module.exports = {
  createOrder,
  getOrder,
  attachPaymentAttempt,
  recordPaymentReference,
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
};
