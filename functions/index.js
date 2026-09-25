const { onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { setGlobalOptions } = require("firebase-functions/v2");
const { admin } = require("./lib/firebaseAdmin");
const { CJ_API_KEY } = require("./lib/cjAuth");
const cjApi = require("./lib/cjApi");
const intasend = require("./lib/intasendApi");
const paypal = require("./lib/paypalApi");
const orders = require("./lib/orders");
const subscriptions = require("./lib/subscriptions");
const refunds = require("./lib/refunds");
const reviews = require("./lib/reviews");
const catalogSync = require("./lib/catalogSync");
const { refreshFxRates } = require("./lib/fx");
const { ALERTS, logAlert, logError, logInfo, logWarning } = require("./lib/logging");
const {
  clampPage,
  clampPageSize,
  sanitizeKeyword,
  sanitizeId,
  validateFreightRequest,
  isValidMpesaPhone,
  isAllowedRedirectUrl,
} = require("./lib/params");
const { publicError } = require("./lib/errors");
const { checkRateLimit } = require("./lib/rateLimit");

setGlobalOptions({ region: "us-central1", maxInstances: 10 });

// Least privilege: an endpoint only gets the credentials it actually uses, so
// a compromised M-Pesa push can't read the PayPal ones. The CJ key is only
// needed where fulfillment can happen (a confirm/capture/webhook pushes the
// order to CJ) - starting a payment never touches CJ.
const CJ_SECRETS = [CJ_API_KEY];
const INTASEND_SECRETS = [intasend.INTASEND_SECRET_KEY];
const INTASEND_FULFILL_SECRETS = [intasend.INTASEND_SECRET_KEY, CJ_API_KEY];
const PAYPAL_SECRETS = [paypal.PAYPAL_CLIENT_ID, paypal.PAYPAL_CLIENT_SECRET];
const PAYPAL_FULFILL_SECRETS = [...PAYPAL_SECRETS, CJ_API_KEY];
const PAYPAL_WEBHOOK_SECRETS = [...PAYPAL_FULFILL_SECRETS, paypal.PAYPAL_WEBHOOK_ID];
// The one deliberate exception to the split above: a refund has to reach
// whichever provider took the money, and which one that was is a property of
// the order, not of the request. Splitting it per provider would mean the
// caller choosing the endpoint from data only the server can be trusted to
// read. It's admin-only and it's the endpoint that moves money back out.
const REFUND_SECRETS = [intasend.INTASEND_SECRET_KEY, ...PAYPAL_SECRETS];

// Browsing and checkout have opposite traffic shapes: browsing is public,
// spiky and cheap to serve; checkout is low-volume and must complete. Giving
// them separate instance ceilings keeps a browse spike - or a scraper - from
// eating the capacity a paying customer needs.
const BROWSE_MAX_INSTANCES = 30;
const CHECKOUT_MAX_INSTANCES = 10;

/**
 * @param {Array<object>} secrets Secrets this endpoint may read.
 * @return {object} onRequest options for a checkout/payment endpoint.
 */
function checkoutOptions(secrets) {
  return { secrets, cors: true, maxInstances: CHECKOUT_MAX_INSTANCES };
}

const BROWSE_OPTIONS = {
  secrets: CJ_SECRETS,
  cors: true,
  maxInstances: BROWSE_MAX_INSTANCES,
};

// App Check is what separates our app from anyone curling these public URLs.
// It stays in report-only mode until the Flutter client actually sends tokens
// (see TODO.md Phase 3) - turning it on before then would lock out the app -
// at which point `ENFORCE_APP_CHECK=true` in functions/.env starts rejecting
// everything else.
const APP_CHECK_ENFORCED = process.env.ENFORCE_APP_CHECK === "true";

/**
 * @param {object} req Express request.
 * @param {object} res Express response, used to write 401 when enforcing.
 * @param {string} endpoint Endpoint name, for the log entry.
 * @return {Promise<boolean>} Whether the handler may continue.
 */
async function appCheckPassed(req, res, endpoint) {
  const token = req.header("X-Firebase-AppCheck");
  if (token) {
    try {
      await admin.appCheck().verifyToken(token);
      return true;
    } catch (err) {
      logWarning("app_check_token_invalid", { endpoint }, err);
    }
  }
  if (!APP_CHECK_ENFORCED) return true;
  res.status(401).json({ success: false, message: "App Check verification failed" });
  return false;
}

// Order currencies PayPal can actually settle. KES is deliberately absent -
// PayPal does not support it, so those orders are IntaSend-only.
const PAYPAL_CURRENCIES = ["USD", "EUR", "GBP"];

// ---------------------------------------------------------------------------
// Optional helper: verify a Firebase Auth ID token sent by the Flutter app as
// `Authorization: Bearer <idToken>`. Call this inside a handler and return 401
// if you want an endpoint restricted to signed-in users (e.g. before checkout).
// Product browsing endpoints below are left public since that's normal for a
// storefront, but the helper is here ready to use.
// ---------------------------------------------------------------------------
async function verifyAuth(req) {
  const header = req.headers.authorization || "";
  const match = header.match(/^Bearer (.+)$/);
  if (!match) return null;
  try {
    // checkRevoked: without it, a token stays valid for up to an hour after
    // the account is disabled or its sessions revoked - long enough for a
    // suspended account to keep placing orders and starting payments.
    return await admin.auth().verifyIdToken(match[1], true);
  } catch {
    return null;
  }
}

/**
 * Fails a request, recording which endpoint failed and for whose order - the
 * context that makes a payment failure debuggable from the logs alone.
 *
 * Only an `HttpError`'s message reaches the caller (see lib/errors.js);
 * anything else - a CJ or IntaSend error body, a Firestore path - is logged
 * in full here and answered with a generic 500.
 * @param {object} res Express response.
 * @param {Error} err The failure.
 * @param {object=} context `{ endpoint, uid, orderId }`.
 */
function sendError(res, err, context = {}) {
  const { status, message } = publicError(err);
  if (status >= 500) {
    logError("request_failed", context, err);
  } else {
    logWarning("request_rejected", { ...context, status, reason: message });
  }
  res.status(status).json({ success: false, message });
}

/**
 * Counts this call against the caller's per-user budget (lib/rateLimit.js),
 * writing a 429 with Retry-After and returning false once it's spent.
 * @param {object} res Express response.
 * @param {string} policy Key of rateLimit.POLICIES.
 * @param {string} uid Caller's Firebase Auth uid.
 * @return {Promise<boolean>} Whether the handler may continue.
 */
async function withinRateLimit(res, policy, uid) {
  const { allowed, retryAfterMs } = await checkRateLimit(policy, uid);
  if (allowed) return true;
  logWarning("rate_limited", { policy, uid });
  res.set("Retry-After", String(Math.max(1, Math.ceil(retryAfterMs / 1000))));
  res.status(429).json({
    success: false,
    message: "Too many requests. Please wait a moment and try again.",
  });
  return false;
}

/**
 * A payment provider's post-checkout redirect must point back at our own
 * app (see params.isAllowedRedirectUrl). Omitted is fine - the mobile app
 * sends none.
 * @param {object} res Express response, used to write 400 on failure.
 * @param {object} urls Named URLs from the request body.
 * @return {boolean} Whether the handler may continue.
 */
function redirectsAllowed(res, urls) {
  for (const [name, value] of Object.entries(urls)) {
    if (value === undefined || value === null || value === "") continue;
    if (!isAllowedRedirectUrl(value)) {
      res.status(400).json({ success: false, message: `${name} is not an allowed URL` });
      return false;
    }
  }
  return true;
}

// Lightweight backend reachability probe used by the Flutter network manager.
// It intentionally has no secret/auth requirement and no database/API work.
exports.health = onRequest({ cors: true }, (req, res) => {
  res.status(200).json({ status: "ok" });
});

/** Returns the decoded Firebase ID token, or writes a 401 response and returns null. */
async function requireAuth(req, res) {
  const decoded = await verifyAuth(req);
  if (!decoded) {
    res.status(401).json({ success: false, message: "Sign-in required" });
    return null;
  }
  return decoded;
}

/**
 * Loads an order and checks the caller owns it, writing the appropriate
 * 400/403 response and returning null if not. Used by every payment
 * endpoint below so ownership is always re-checked server-side, never
 * trusting the client.
 * @param {object} res Express response, used to write 400/403 on failure.
 * @param {string} orderId Order document id.
 * @param {string} uid Caller's Firebase Auth uid.
 * @return {Promise<object|null>} The order, or null if a response was sent.
 */
async function loadOwnedOrder(res, orderId, uid) {
  // sanitizeId also refuses anything containing "/", which would otherwise
  // address a different document path than orders/{orderId}.
  if (!sanitizeId(orderId)) {
    res.status(400).json({ success: false, message: "A valid orderId is required" });
    return null;
  }
  const order = await orders.getOrder(orderId);
  if (order.uid !== uid) {
    res.status(403).json({ success: false, message: "Forbidden" });
    return null;
  }
  return order;
}

/**
 * Same as `loadOwnedOrder`, but additionally refuses an order that can't
 * accept a new payment attempt: one already paid, or one that already has a
 * live attempt with this same method. Both would otherwise leave the customer
 * charged twice - the second case because two STK prompts can sit on a phone
 * at once and only the latest invoice is the one we poll.
 * @param {object} res Express response, used to write the failure status.
 * @param {string} orderId Order document id.
 * @param {string} uid Caller's Firebase Auth uid.
 * @param {string} paymentMethod Method about to be started, as stored on the
 *   order (e.g. "MPESA", "CARD", "GOOGLE_PAY", "PAYPAL").
 * @return {Promise<object|null>} The order, or null if a response was sent.
 */
async function loadPayableOrder(res, orderId, uid, paymentMethod) {
  const order = await loadOwnedOrder(res, orderId, uid);
  if (!order) return null;
  if (order.paymentStatus === "paid") {
    res.status(409).json({ success: false, message: "Order is already paid" });
    return null;
  }
  if (orders.hasPendingAttempt(order, paymentMethod)) {
    res.status(409).json({
      success: false,
      message: "A payment for this order is already in progress",
    });
    return null;
  }
  return order;
}

/**
 * GET /getCategories
 * Returns CJ's full category tree.
 */
exports.getCategories = onRequest(BROWSE_OPTIONS, async (req, res) => {
  if (!await appCheckPassed(req, res, "getCategories")) return;
  try {
    const data = await cjApi.fetchCategories();
    res.status(200).json({ success: true, data });
  } catch (err) {
    sendError(res, err, { endpoint: "getCategories" });
  }
});

/**
 * GET /searchProducts?keyword=hoodie&categoryId=xxx&page=1&size=20
 * Returns a paginated, flattened product list ready for a Flutter ListView/GridView.
 *
 * Every parameter is clamped before it reaches CJ: this endpoint is public and
 * spends our one CJ API key, so an unbounded `size` or `page` is a way to get
 * that key rate-limited and take the catalog offline for everyone.
 */
exports.searchProducts = onRequest(BROWSE_OPTIONS, async (req, res) => {
  if (!await appCheckPassed(req, res, "searchProducts")) return;
  try {
    const { keyword, categoryId, page, size, region } = req.query;
    const data = await cjApi.searchProducts({
      keyword: sanitizeKeyword(keyword),
      categoryId: sanitizeId(categoryId),
      page: clampPage(page),
      size: clampPageSize(size),
      regionKey: sanitizeId(region),
    });
    res.status(200).json({ success: true, data });
  } catch (err) {
    sendError(res, err, { endpoint: "searchProducts" });
  }
});

/**
 * GET /getProductDetail?pid=xxxxxxxx
 * Returns product info + all its variants in one call.
 */
exports.getProductDetail = onRequest(BROWSE_OPTIONS, async (req, res) => {
  if (!await appCheckPassed(req, res, "getProductDetail")) return;
  try {
    const pid = sanitizeId(req.query.pid);
    if (!pid) {
      return res.status(400).json({ success: false, message: "A valid pid is required" });
    }
    const data = await cjApi.getProductDetail(pid, sanitizeId(req.query.region));
    res.status(200).json({ success: true, data });
  } catch (err) {
    sendError(res, err, { endpoint: "getProductDetail" });
  }
});

/**
 * POST /calculateFreight
 * body: { endCountryCode: "US", startCountryCode?: "CN", products: [{ vid, quantity }] }
 * Use this at checkout to show real shipping cost/time before the user pays.
 */
exports.calculateFreight = onRequest(checkoutOptions(CJ_SECRETS), async (req, res) => {
  if (req.method !== "POST") {
    return res.status(405).json({ success: false, message: "Use POST" });
  }
  const user = await requireAuth(req, res);
  if (!user) return;
  if (!await withinRateLimit(res, "calculateFreight", user.uid)) return;
  try {
    const request = validateFreightRequest(req.body);
    if (request.error) {
      return res.status(400).json({ success: false, message: request.error });
    }
    const data = await cjApi.calculateFreight(request.value);
    res.status(200).json({ success: true, data });
  } catch (err) {
    sendError(res, err, { endpoint: "calculateFreight", uid: user.uid });
  }
});

// =============================================================================
// Orders
// =============================================================================

/**
 * POST /createOrder   (auth required)
 * body: { items: [{ pid, vid, quantity }], shippingAddress: {...}, storeId,
 *   logisticName?: string }
 * Prices everything from CJ's live prices + the selling store's own listed
 * price, returns totals in both USD (for PayPal) and KES (for M-Pesa/card/
 * Google Pay via IntaSend).
 * `storeId` is the store the buyer is checking out from - required; every
 * item must be listed and published in that store.
 * `logisticName` is the buyer's chosen CJ shipping line from `calculateFreight`
 * (omit it to auto-pick the cheapest) - only the name is trusted, never a price.
 */
exports.createOrder = onRequest(checkoutOptions(CJ_SECRETS), async (req, res) => {
  const user = await requireAuth(req, res);
  if (!user) return;
  if (!await withinRateLimit(res, "createOrder", user.uid)) return;
  try {
    const { items, shippingAddress, logisticName, storeId } = req.body || {};
    const order = await orders.createOrder({ uid: user.uid, items, shippingAddress, logisticName, storeId });
    logInfo("order_created", {
      orderId: order.id,
      uid: user.uid,
      currency: order.currency,
      totalAmount: order.totalAmount,
    });
    res.status(200).json({ success: true, data: order });
  } catch (err) {
    sendError(res, err, { endpoint: "createOrder", uid: user.uid });
  }
});

/**
 * POST /getOrderTracking   (auth required)
 * body: { orderId, force?: boolean }
 * Where the parcel actually is. Asks CJ when the stored snapshot is stale
 * (see tracking.shouldRefreshTracking) and returns it either way, so the
 * screen always renders something rather than an empty state while a CJ
 * lookup is in flight.
 *
 * The app can read the same snapshot straight off the order document; this
 * endpoint exists to *refresh* it, since only the server may talk to CJ.
 */
exports.getOrderTracking = onRequest(checkoutOptions(CJ_SECRETS), async (req, res) => {
  const user = await requireAuth(req, res);
  if (!user) return;
  if (!await withinRateLimit(res, "orderTracking", user.uid)) return;
  try {
    const { orderId, force } = req.body || {};
    const order = await loadOwnedOrder(res, orderId, user.uid);
    if (!order) return;
    if (!order.cjOrderId) {
      // Paid but not yet with CJ, or a push that hasn't succeeded yet.
      // That's a normal state for a few minutes after checkout, and a
      // legitimate answer rather than an error.
      return res.status(200).json({
        success: true,
        data: {
          tracking: null,
          status: order.status,
          cjOrderStatus: order.cjOrderStatus || "NOT_PUSHED",
          refreshed: false,
          reason: "not_pushed",
        },
      });
    }
    const result = await orders.refreshOrderTracking(orderId, {
      force: force === true,
    });
    res.status(200).json({
      success: true,
      data: {
        tracking: result.tracking,
        status: result.status || order.status,
        cjOrderStatus: order.cjOrderStatus,
        refreshed: result.refreshed,
        reason: result.reason,
      },
    });
  } catch (err) {
    sendError(res, err, {
      endpoint: "getOrderTracking",
      uid: user.uid,
      orderId: req.body?.orderId,
    });
  }
});

// Refusal reasons from `refunds.decideRefund`, as something a support agent
// can act on rather than a code they have to look up.
const REFUND_REFUSALS = Object.freeze({
  not_paid: "This order was never paid, so there is nothing to refund",
  no_charge_to_refund: "This order has no recorded charge to refund",
  refund_in_progress: "A refund for this order is already being processed",
  already_refunded: "This order has already been fully refunded",
  invalid_amount: "The refund amount must be a positive number",
  exceeds_remaining: "That is more than the amount left to refund on this order",
});

/**
 * POST /refundOrder   (admin only)
 * body: { orderId, amount?, reason?, comment? }
 * Refunds through whichever provider took the payment and records it on the
 * order. Omitting `amount` refunds everything not already refunded.
 *
 * Admin-gated on the same `admin` custom claim as `runCatalogSync`: this
 * moves money out, and there is no customer-facing self-service refund - a
 * refund request goes through support, who run this.
 */
exports.refundOrder = onRequest(checkoutOptions(REFUND_SECRETS), async (req, res) => {
  const user = await requireAuth(req, res);
  if (!user) return;
  if (user.admin !== true) {
    return res.status(403).json({ success: false, message: "Forbidden" });
  }
  try {
    const { orderId, amount, reason, comment } = req.body || {};
    if (!sanitizeId(orderId)) {
      return res.status(400).json({ success: false, message: "A valid orderId is required" });
    }
    const result = await refunds.refundOrder({
      orderId,
      amount,
      reason,
      comment,
      actorUid: user.uid,
    });
    if (!result.ok) {
      // A refusal is about the order's state, not a server fault: 409 for
      // "the order isn't in a state to be refunded", 400 for a bad amount.
      const status = result.reason === "invalid_amount" ||
        result.reason === "exceeds_remaining" ? 400 : 409;
      return res.status(status).json({
        success: false,
        message: REFUND_REFUSALS[result.reason] || result.reason,
        reason: result.reason,
      });
    }
    res.status(200).json({ success: true, data: result });
  } catch (err) {
    sendError(res, err, {
      endpoint: "refundOrder",
      uid: user.uid,
      orderId: req.body?.orderId,
    });
  }
});

// =============================================================================
// Reviews
// =============================================================================

/**
 * POST /submitProductReview   (auth required)
 * body: { productId, rating, comment }
 * Creates or updates the caller's review (one per user per product) and
 * keeps products/{productId}'s ratingAvg/ratingCount/ratingBreakdown in
 * sync in the same transaction. verifiedPurchase is computed server-side
 * from the caller's paid orders, never trusted from the client.
 */
exports.submitProductReview = onRequest({ cors: true }, async (req, res) => {
  const user = await requireAuth(req, res);
  if (!user) return;
  if (!await withinRateLimit(res, "review", user.uid)) return;
  try {
    const { productId, rating, comment } = req.body || {};
    const result = await reviews.submitReview({
      uid: user.uid,
      decoded: user,
      productId,
      rating: Number(rating),
      comment,
    });
    res.status(200).json({ success: true, data: result });
  } catch (err) {
    sendError(res, err, { endpoint: "submitProductReview", uid: user.uid });
  }
});

/**
 * POST /deleteProductReview   (auth required)
 * body: { productId }
 * Removes the caller's own review and re-syncs the product's aggregate.
 */
exports.deleteProductReview = onRequest({ cors: true }, async (req, res) => {
  const user = await requireAuth(req, res);
  if (!user) return;
  if (!await withinRateLimit(res, "review", user.uid)) return;
  try {
    const { productId } = req.body || {};
    await reviews.deleteReview({ uid: user.uid, productId });
    res.status(200).json({ success: true });
  } catch (err) {
    sendError(res, err, { endpoint: "deleteProductReview", uid: user.uid });
  }
});

// =============================================================================
// IntaSend - M-Pesa / Card / Google Pay
// =============================================================================

/**
 * POST /payOrderMpesa   (auth required)
 * body: { orderId, phoneNumber }   phoneNumber format: 2547XXXXXXXX
 * Triggers an STK push. The customer approves on their phone, then the app
 * should call /confirmIntasendPayment to check status (or wait for the webhook).
 */
exports.payOrderMpesa = onRequest(checkoutOptions(INTASEND_SECRETS), async (req, res) => {
  const user = await requireAuth(req, res);
  if (!user) return;
  if (!await withinRateLimit(res, "mpesaPush", user.uid)) return;
  try {
    const { orderId, phoneNumber } = req.body || {};
    if (!isValidMpesaPhone(phoneNumber)) {
      return res.status(400).json({
        success: false,
        message: "phoneNumber must be a Kenyan M-Pesa number in the form 2547XXXXXXXX",
      });
    }
    const order = await loadPayableOrder(res, orderId, user.uid, "MPESA");
    if (!order) return;
    // M-Pesa has hard per-transaction limits. Checking here turns what would
    // be an opaque IntaSend error into an answer the customer can act on.
    const amountError = intasend.mpesaAmountError(order.totalKes);
    if (amountError) {
      return res.status(400).json({ success: false, message: amountError });
    }

    const result = await intasend.mpesaStkPush({
      amount: order.totalKes,
      phoneNumber,
      apiRef: orderId,
      email: user.email,
    });
    await orders.attachPaymentAttempt(orderId, {
      paymentMethod: "MPESA",
      paymentProvider: "INTASEND",
      paymentRef: { invoiceId: result.invoiceId },
    });
    res.status(200).json({ success: true, data: { invoiceId: result.invoiceId } });
  } catch (err) {
    sendError(res, err, {
      endpoint: "payOrderMpesa",
      uid: user.uid,
      orderId: req.body?.orderId,
    });
  }
});

/**
 * POST /payOrderCard   (auth required)
 * body: { orderId, method, redirectUrl }   method: 'CARD-PAYMENT' | 'GOOGLE-PAY'
 * Returns a checkoutUrl - open it in a WebView. IntaSend redirects to
 * redirectUrl when done; call /confirmIntasendPayment afterwards.
 */
exports.payOrderCard = onRequest(checkoutOptions(INTASEND_SECRETS), async (req, res) => {
  const user = await requireAuth(req, res);
  if (!user) return;
  if (!await withinRateLimit(res, "hostedCheckout", user.uid)) return;
  try {
    const { orderId, method, redirectUrl } = req.body || {};
    if (!["CARD-PAYMENT", "GOOGLE-PAY"].includes(method)) {
      return res.status(400).json({ success: false, message: "method must be CARD-PAYMENT or GOOGLE-PAY" });
    }
    if (!redirectsAllowed(res, { redirectUrl })) return;
    const paymentMethod = method === "CARD-PAYMENT" ? "CARD" : "GOOGLE_PAY";
    const order = await loadPayableOrder(res, orderId, user.uid, paymentMethod);
    if (!order) return;

    const result = await intasend.createCheckout({
      amount: order.totalKes,
      currency: "KES",
      method,
      apiRef: orderId,
      email: user.email,
      redirectUrl,
    });
    await orders.attachPaymentAttempt(orderId, {
      paymentMethod,
      paymentProvider: "INTASEND",
      paymentRef: { checkoutId: result.checkoutId },
    });
    res.status(200).json({ success: true, data: { checkoutUrl: result.checkoutUrl } });
  } catch (err) {
    sendError(res, err, {
      endpoint: "payOrderCard",
      uid: user.uid,
      orderId: req.body?.orderId,
    });
  }
});

/**
 * POST /confirmIntasendPayment   (auth required)
 * body: { orderId }
 * Re-checks payment status directly with IntaSend (never trusts the client),
 * and if complete, marks the order paid and pushes it to CJ.
 */
exports.confirmIntasendPayment = onRequest(checkoutOptions(INTASEND_FULFILL_SECRETS), async (req, res) => {
  const user = await requireAuth(req, res);
  if (!user) return;
  if (!await withinRateLimit(res, "confirmPayment", user.uid)) return;
  try {
    const { orderId } = req.body || {};
    const order = await loadOwnedOrder(res, orderId, user.uid);
    if (!order) return;
    if (!order.paymentRef?.invoiceId && !order.paymentRef?.checkoutId) {
      return res.status(400).json({
        success: false,
        message: "No IntaSend payment has been started for this order",
      });
    }

    const status = await intasend.checkPaymentStatus({
      invoiceId: order.paymentRef?.invoiceId,
      checkoutId: order.paymentRef?.checkoutId,
    });

    if (status.isComplete) {
      const check = intasend.verifyAmount(status.raw, {
        amount: order.totalKes,
        currency: "KES",
      });
      if (!check.ok) {
        logAlert(ALERTS.PAYMENT_AMOUNT_MISMATCH, {
          orderId,
          uid: user.uid,
          provider: "INTASEND",
          source: "confirmIntasendPayment",
          expected: { amount: order.totalKes, currency: "KES" },
          actual: check.actual,
        });
        return res.status(409).json({
          success: false,
          message: "The amount paid does not match this order",
        });
      }
      const result = await orders.fulfillOrder(orderId);
      return res.status(200).json({ success: true, data: { paid: true, ...result } });
    }
    res.status(200).json({ success: true, data: { paid: false, state: status.state } });
  } catch (err) {
    sendError(res, err, {
      endpoint: "confirmIntasendPayment",
      uid: user.uid,
      orderId: req.body?.orderId,
    });
  }
});

/**
 * POST /intasendWebhook   (public - configure this URL in your IntaSend dashboard)
 * We deliberately don't trust the payload's own status field - we re-verify
 * with checkPaymentStatus() before fulfilling.
 *
 * Re-verifying the invoice is NOT on its own enough, because `invoice_id` and
 * `api_ref` arrive as two independent values on a public URL: pairing a
 * genuinely-completed invoice with someone else's orderId would otherwise
 * fulfill that order for free. So the invoice must also be one this order
 * actually started before it's allowed to pay for it.
 */
exports.intasendWebhook = onRequest(checkoutOptions(INTASEND_FULFILL_SECRETS), async (req, res) => {
  try {
    const body = req.body || {};
    const invoiceId = body.invoice_id || body.invoice?.invoice_id;
    const orderId = body.api_ref || body.invoice?.api_ref;
    if (!invoiceId || !orderId) {
      return res.status(400).json({ success: false, message: "Missing invoice_id/api_ref" });
    }

    // api_ref may address either an order or a pending subscription billing
    // entry (see the "Subscriptions / Billing" section below). Checking
    // billing_history first is a cheap, targeted lookup that returns null
    // rather than throwing for the common case of an api_ref that's really
    // an order id - orders.getOrder() throws for a truly-unknown id, which
    // is exactly the behaviour we still want once we fall through below.
    const billingEntry = await subscriptions.getBillingEntry(orderId);
    if (billingEntry) {
      if (!subscriptions.isPayable(billingEntry)) {
        // Already handled - a webhook retry after we've already activated
        // this subscription (or already marked it failed) is a no-op.
        return res.status(200).json({
          success: true,
          data: { paid: billingEntry.status === "paid" },
        });
      }
      if (!subscriptions.billingRefMatches(billingEntry, { invoiceId })) {
        logAlert(ALERTS.WEBHOOK_SIGNATURE_INVALID, {
          provider: "INTASEND",
          billingEntryId: orderId,
          invoiceId,
          reason: "invoice was never started for this billing entry",
        });
        return res.status(200).json({
          success: false,
          message: "Invoice does not belong to this billing entry",
        });
      }
      const billingStatus = await intasend.checkPaymentStatus({ invoiceId });
      if (!billingStatus.isComplete) {
        return res.status(200).json({
          success: true,
          data: { paid: false, state: billingStatus.state },
        });
      }
      const billingCheck = intasend.verifyAmount(billingStatus.raw, {
        amount: billingEntry.amountKes,
        currency: "KES",
      });
      if (!billingCheck.ok) {
        logAlert(ALERTS.PAYMENT_AMOUNT_MISMATCH, {
          billingEntryId: orderId,
          sellerId: billingEntry.sellerId,
          provider: "INTASEND",
          source: "intasendWebhook",
          invoiceId,
          expected: { amount: billingEntry.amountKes, currency: "KES" },
          actual: billingCheck.actual,
        });
        return res.status(200).json({ success: false, message: "Amount mismatch" });
      }
      const activation = await subscriptions.activatePendingSubscription(orderId, {
        paymentReference: invoiceId,
      });
      return res.status(200).json({ success: true, data: activation });
    }

    const order = await orders.getOrder(orderId);
    if (!orders.paymentRefMatches(order, { invoiceId })) {
      logAlert(ALERTS.WEBHOOK_SIGNATURE_INVALID, {
        provider: "INTASEND",
        orderId,
        invoiceId,
        reason: "invoice was never started for this order",
      });
      return res.status(200).json({
        success: false,
        message: "Invoice does not belong to this order",
      });
    }

    const status = await intasend.checkPaymentStatus({ invoiceId });
    if (!status.isComplete) {
      return res.status(200).json({ success: true, data: { paid: false, state: status.state } });
    }

    const check = intasend.verifyAmount(status.raw, {
      amount: order.totalKes,
      currency: "KES",
    });
    if (!check.ok) {
      logAlert(ALERTS.PAYMENT_AMOUNT_MISMATCH, {
        orderId,
        uid: order.uid,
        provider: "INTASEND",
        source: "intasendWebhook",
        invoiceId,
        expected: { amount: order.totalKes, currency: "KES" },
        actual: check.actual,
      });
      return res.status(200).json({ success: false, message: "Amount mismatch" });
    }
    if (!check.actual) {
      logWarning("intasend_amount_unreadable", {
        orderId,
        invoiceId,
        note: "fulfilled on the invoice binding alone; confirm IntaSend's status response shape",
      });
    }

    const result = await orders.fulfillOrder(orderId);
    res.status(200).json({ success: true, data: result });
  } catch (err) {
    logError("request_failed", {
      endpoint: "intasendWebhook",
      orderId: req.body?.api_ref || req.body?.invoice?.api_ref,
    }, err);
    // Still ack with 200 so IntaSend doesn't hammer retries for a bug on our
    // side while we investigate; the order can be reconciled manually. This
    // URL is public, so the body carries the generic message, not err's.
    res.status(200).json({ success: false, message: publicError(err).message });
  }
});

// =============================================================================
// Subscriptions / Billing (seller plans)
// =============================================================================
//
// Mirrors the order-payment endpoints above exactly (same requireAuth/
// checkoutOptions/{success,data} shape, same intasend.mpesaStkPush/
// createCheckout/checkPaymentStatus primitives, unchanged), swapping an
// `orders/{id}` doc for a `billing_history/{id}` doc as the thing being
// paid for. See functions/lib/subscriptions.js and firestore.rules'
// `subscriptions/{sellerId}` block.
//
// Not done here: order-limit enforcement inside createOrder above - the new
// orders.js has no sellerId field to key a per-seller count on yet (see
// WORKLOG.md, 2026-09-12). This billing flow is otherwise self-contained.

/**
 * POST /subscribeSeller   (auth required)
 * body: { planId }
 * Starts a subscription purchase: creates a pending billing_history entry,
 * snapshotting the plan's price server-side (never trusting a client-sent
 * amount). Does NOT activate anything - only a confirmed payment does, via
 * confirmBillingPayment or intasendWebhook above.
 */
exports.subscribeSeller = onRequest(checkoutOptions([]), async (req, res) => {
  const user = await requireAuth(req, res);
  if (!user) return;
  if (!await withinRateLimit(res, "subscribe", user.uid)) return;
  try {
    const { planId } = req.body || {};
    if (!planId || typeof planId !== "string") {
      return res.status(400).json({ success: false, message: "planId is required" });
    }
    const entry = await subscriptions.createBillingEntry({ sellerId: user.uid, planId });
    res.status(200).json({ success: true, data: entry });
  } catch (err) {
    sendError(res, err, { endpoint: "subscribeSeller", uid: user.uid });
  }
});

/**
 * Loads a billing_history entry and checks the caller owns it, writing the
 * appropriate 400/403/409 response and returning null if not. Mirrors
 * loadPayableOrder above.
 * @param {object} res Express response.
 * @param {string} entryId
 * @param {string} uid Caller's Firebase Auth uid.
 * @return {Promise<object|null>}
 */
async function loadPayableBillingEntry(res, entryId, uid) {
  if (!sanitizeId(entryId)) {
    res.status(400).json({ success: false, message: "A valid billingEntryId is required" });
    return null;
  }
  const entry = await subscriptions.getBillingEntry(entryId);
  if (!entry || entry.sellerId !== uid) {
    res.status(403).json({ success: false, message: "Forbidden" });
    return null;
  }
  if (!subscriptions.isPayable(entry)) {
    res.status(409).json({ success: false, message: "This billing entry is no longer payable" });
    return null;
  }
  return entry;
}

/**
 * POST /payBillingMpesa   (auth required)
 * body: { billingEntryId, phoneNumber }   phoneNumber format: 2547XXXXXXXX
 * Exact structural mirror of /payOrderMpesa - see that handler's doc comment.
 */
exports.payBillingMpesa = onRequest(checkoutOptions(INTASEND_SECRETS), async (req, res) => {
  const user = await requireAuth(req, res);
  if (!user) return;
  if (!await withinRateLimit(res, "mpesaPush", user.uid)) return;
  try {
    const { billingEntryId, phoneNumber } = req.body || {};
    if (!isValidMpesaPhone(phoneNumber)) {
      return res.status(400).json({
        success: false,
        message: "phoneNumber must be a Kenyan M-Pesa number in the form 2547XXXXXXXX",
      });
    }
    const entry = await loadPayableBillingEntry(res, billingEntryId, user.uid);
    if (!entry) return;
    const amountError = intasend.mpesaAmountError(entry.amountKes);
    if (amountError) {
      return res.status(400).json({ success: false, message: amountError });
    }

    const result = await intasend.mpesaStkPush({
      amount: entry.amountKes,
      phoneNumber,
      apiRef: billingEntryId,
      email: user.email,
    });
    await subscriptions.attachBillingPaymentAttempt(billingEntryId, {
      paymentMethod: "MPESA",
      paymentProvider: "INTASEND",
      paymentRef: { invoiceId: result.invoiceId },
    });
    res.status(200).json({ success: true, data: { invoiceId: result.invoiceId } });
  } catch (err) {
    sendError(res, err, {
      endpoint: "payBillingMpesa",
      uid: user.uid,
      billingEntryId: req.body?.billingEntryId,
    });
  }
});

/**
 * POST /payBillingCard   (auth required)
 * body: { billingEntryId, method, redirectUrl }   method: 'CARD-PAYMENT' | 'GOOGLE-PAY'
 * Exact structural mirror of /payOrderCard - see that handler's doc comment.
 */
exports.payBillingCard = onRequest(checkoutOptions(INTASEND_SECRETS), async (req, res) => {
  const user = await requireAuth(req, res);
  if (!user) return;
  if (!await withinRateLimit(res, "hostedCheckout", user.uid)) return;
  try {
    const { billingEntryId, method, redirectUrl } = req.body || {};
    if (!["CARD-PAYMENT", "GOOGLE-PAY"].includes(method)) {
      return res.status(400).json({ success: false, message: "method must be CARD-PAYMENT or GOOGLE-PAY" });
    }
    if (!redirectsAllowed(res, { redirectUrl })) return;
    const entry = await loadPayableBillingEntry(res, billingEntryId, user.uid);
    if (!entry) return;
    const paymentMethod = method === "CARD-PAYMENT" ? "CARD" : "GOOGLE_PAY";

    const result = await intasend.createCheckout({
      amount: entry.amountKes,
      currency: "KES",
      method,
      apiRef: billingEntryId,
      email: user.email,
      redirectUrl,
    });
    await subscriptions.attachBillingPaymentAttempt(billingEntryId, {
      paymentMethod,
      paymentProvider: "INTASEND",
      paymentRef: { checkoutId: result.checkoutId },
    });
    res.status(200).json({ success: true, data: { checkoutUrl: result.checkoutUrl } });
  } catch (err) {
    sendError(res, err, {
      endpoint: "payBillingCard",
      uid: user.uid,
      billingEntryId: req.body?.billingEntryId,
    });
  }
});

/**
 * POST /confirmBillingPayment   (auth required)
 * body: { billingEntryId }
 * Re-checks payment status directly with IntaSend (never trusts the
 * client), and if complete, activates the subscription. Exact structural
 * mirror of /confirmIntasendPayment.
 */
exports.confirmBillingPayment = onRequest(checkoutOptions(INTASEND_SECRETS), async (req, res) => {
  const user = await requireAuth(req, res);
  if (!user) return;
  if (!await withinRateLimit(res, "confirmPayment", user.uid)) return;
  try {
    const { billingEntryId } = req.body || {};
    if (!sanitizeId(billingEntryId)) {
      return res.status(400).json({ success: false, message: "A valid billingEntryId is required" });
    }
    const entry = await subscriptions.getBillingEntry(billingEntryId);
    if (!entry || entry.sellerId !== user.uid) {
      return res.status(403).json({ success: false, message: "Forbidden" });
    }
    if (!subscriptions.isPayable(entry)) {
      return res.status(200).json({ success: true, data: { paid: entry.status === "paid" } });
    }
    if (!entry.paymentRef?.invoiceId && !entry.paymentRef?.checkoutId) {
      return res.status(400).json({
        success: false,
        message: "No IntaSend payment has been started for this billing entry",
      });
    }

    const status = await intasend.checkPaymentStatus({
      invoiceId: entry.paymentRef?.invoiceId,
      checkoutId: entry.paymentRef?.checkoutId,
    });

    if (status.isComplete) {
      const check = intasend.verifyAmount(status.raw, {
        amount: entry.amountKes,
        currency: "KES",
      });
      if (!check.ok) {
        logAlert(ALERTS.PAYMENT_AMOUNT_MISMATCH, {
          billingEntryId,
          uid: user.uid,
          provider: "INTASEND",
          source: "confirmBillingPayment",
          expected: { amount: entry.amountKes, currency: "KES" },
          actual: check.actual,
        });
        return res.status(409).json({
          success: false,
          message: "The amount paid does not match this billing entry",
        });
      }
      const result = await subscriptions.activatePendingSubscription(billingEntryId, {
        paymentReference: entry.paymentRef?.invoiceId,
      });
      return res.status(200).json({ success: true, data: { paid: true, ...result } });
    }
    res.status(200).json({ success: true, data: { paid: false, state: status.state } });
  } catch (err) {
    sendError(res, err, {
      endpoint: "confirmBillingPayment",
      uid: user.uid,
      billingEntryId: req.body?.billingEntryId,
    });
  }
});

// =============================================================================
// PayPal
// =============================================================================

/**
 * POST /createPaypalOrder   (auth required)
 * body: { orderId, returnUrl, cancelUrl }
 * Returns approveUrl - open it in a WebView for the buyer to log in/approve.
 */
exports.createPaypalOrder = onRequest(checkoutOptions(PAYPAL_SECRETS), async (req, res) => {
  const user = await requireAuth(req, res);
  if (!user) return;
  if (!await withinRateLimit(res, "hostedCheckout", user.uid)) return;
  try {
    const { orderId, returnUrl, cancelUrl } = req.body || {};
    if (!redirectsAllowed(res, { returnUrl, cancelUrl })) return;
    const order = await loadPayableOrder(res, orderId, user.uid, "PAYPAL");
    if (!order) return;
    // PayPal doesn't settle KES at all - a KES order reaching here would fail
    // deep inside PayPal with an opaque error, so reject it up front.
    if (!PAYPAL_CURRENCIES.includes(order.currency)) {
      return res.status(400).json({
        success: false,
        message: `PayPal cannot be used for a ${order.currency} order`,
      });
    }

    const result = await paypal.createOrder({
      amount: order.totalAmount,
      currency: order.currency,
      referenceId: orderId,
      returnUrl,
      cancelUrl,
    });
    await orders.attachPaymentAttempt(orderId, {
      paymentMethod: "PAYPAL",
      paymentProvider: "PAYPAL",
      paymentRef: { paypalOrderId: result.paypalOrderId },
    });
    res.status(200).json({ success: true, data: { approveUrl: result.approveUrl } });
  } catch (err) {
    sendError(res, err, {
      endpoint: "createPaypalOrder",
      uid: user.uid,
      orderId: req.body?.orderId,
    });
  }
});

/**
 * POST /capturePaypalOrder   (auth required)
 * body: { orderId }
 * Call this after the WebView redirects back following buyer approval.
 */
exports.capturePaypalOrder = onRequest(checkoutOptions(PAYPAL_FULFILL_SECRETS), async (req, res) => {
  const user = await requireAuth(req, res);
  if (!user) return;
  if (!await withinRateLimit(res, "confirmPayment", user.uid)) return;
  try {
    const { orderId } = req.body || {};
    const order = await loadOwnedOrder(res, orderId, user.uid);
    if (!order) return;
    if (!order.paymentRef?.paypalOrderId) {
      return res.status(400).json({
        success: false,
        message: "No PayPal payment has been started for this order",
      });
    }

    const capture = await paypal.captureOrder(order.paymentRef.paypalOrderId);
    const amountVerified = capture.amount != null &&
      paypal.verifyAmount(capture.raw, { amount: order.totalAmount, currency: order.currency });
    // PayPal refunds are issued against the capture, not the order, and this
    // is the only point the capture id is ever visible - record it now or
    // the order can never be refunded through the API.
    await orders.recordPaymentReference(orderId, {
      paypalCaptureId: paypal.extractCaptureId(capture.raw),
    });
    if (capture.isCompleted && amountVerified) {
      const result = await orders.fulfillOrder(orderId);
      return res.status(200).json({ success: true, data: { paid: true, ...result } });
    }
    if (capture.isCompleted && !amountVerified) {
      logAlert(ALERTS.PAYMENT_AMOUNT_MISMATCH, {
        orderId,
        uid: user.uid,
        provider: "PAYPAL",
        source: "capturePaypalOrder",
        expected: { amount: order.totalAmount, currency: order.currency },
        actual: capture.amount,
      });
    }
    res.status(200).json({ success: true, data: { paid: false, status: capture.status } });
  } catch (err) {
    sendError(res, err, {
      endpoint: "capturePaypalOrder",
      uid: user.uid,
      orderId: req.body?.orderId,
    });
  }
});

/**
 * POST /paypalWebhook   (public - configure in PayPal Dashboard > Webhooks)
 * Verifies PayPal's signature before doing anything, then re-fetches order
 * state from PayPal (not the webhook payload) before fulfilling.
 */
exports.paypalWebhook = onRequest(checkoutOptions(PAYPAL_WEBHOOK_SECRETS), async (req, res) => {
  try {
    const verified = await paypal.verifyWebhookSignature(req.headers, req.body);
    if (!verified) {
      // Also fires if PAYPAL_WEBHOOK_ID wasn't swapped when going live, in
      // which case every genuine webhook lands here and fulfillment silently
      // falls back to client polling - hence the alert.
      logAlert(ALERTS.WEBHOOK_SIGNATURE_INVALID, {
        provider: "PAYPAL",
        eventType: req.body?.event_type,
      });
      return res.status(400).json({ success: false, message: "Invalid signature" });
    }
    const event = req.body;
    const relevant = ["CHECKOUT.ORDER.APPROVED", "PAYMENT.CAPTURE.COMPLETED"];
    if (!relevant.includes(event.event_type)) {
      return res.status(200).json({ success: true, ignored: true });
    }
    const paypalOrderId =
      event.resource?.id || event.resource?.supplementary_data?.related_ids?.order_id;
    const orderId = event.resource?.purchase_units?.[0]?.reference_id;
    if (paypalOrderId && orderId) {
      const order = await orders.getOrder(orderId);
      const fresh = await paypal.getOrder(paypalOrderId);
      if (fresh.status === "COMPLETED" || fresh.status === "APPROVED") {
        const capture = fresh.status === "APPROVED" ?
          await paypal.captureOrder(paypalOrderId) :
          { amount: null, raw: fresh };
        const verifyAgainst = capture.amount != null ? capture.raw : fresh;
        const amountVerified = paypal.verifyAmount(
            verifyAgainst, { amount: order.totalAmount, currency: order.currency },
        );
        // Same as the capture endpoint: whichever path wins the race has to
        // record the capture id, or the order becomes unrefundable.
        await orders.recordPaymentReference(orderId, {
          paypalCaptureId: paypal.extractCaptureId(verifyAgainst),
        });
        if (amountVerified) {
          await orders.fulfillOrder(orderId);
        } else {
          logAlert(ALERTS.PAYMENT_AMOUNT_MISMATCH, {
            orderId,
            uid: order.uid,
            provider: "PAYPAL",
            source: "paypalWebhook",
            paypalOrderId,
            expected: { amount: order.totalAmount, currency: order.currency },
          });
        }
      }
    }
    res.status(200).json({ success: true });
  } catch (err) {
    logError("request_failed", {
      endpoint: "paypalWebhook",
      eventType: req.body?.event_type,
    }, err);
    res.status(200).json({ success: false, message: publicError(err).message });
  }
});

// =============================================================================
// Scheduled maintenance
// =============================================================================

/**
 * Keeps the cached USD-base FX rates (KES/EUR/GBP) fresh once a day. A failure
 * here is what makes rates go stale, and `getFxDoc` refuses to price from a
 * rate older than its ceiling - so the failure is alerted, not just thrown.
 */
exports.refreshFxRate = onSchedule({ schedule: "every 24 hours", maxInstances: 1 }, async () => {
  try {
    const doc = await refreshFxRates();
    logInfo("fx_refreshed", { rates: doc.rates });
  } catch (err) {
    logAlert(ALERTS.FX_STALE, { outcome: "refresh_failed" }, err);
    throw err;
  }
});

/**
 * Mirrors the configured slice of CJ's catalog into Firestore, which is what
 * the storefront's home/category/wishlist screens actually read. Runs daily;
 * use /runCatalogSync to trigger it on demand.
 */
exports.syncCatalog = onSchedule(
    {
      schedule: "every 24 hours",
      secrets: CJ_SECRETS,
      timeoutSeconds: 540,
      // One sync at a time: two overlapping runs would double the CJ calls
      // for the same result and race each other's writes.
      maxInstances: 1,
    },
    async () => {
      const summary = await catalogSync.runCatalogSync();
      logInfo("catalog_sync_run", { trigger: "schedule", ...summary });
    },
);

/**
 * POST /runCatalogSync   (admin only)
 * Same pass as the scheduled job, on demand - for seeding the catalog the
 * first time and after editing `config/catalog`, without waiting a day.
 */
exports.runCatalogSync = onRequest(
    { secrets: CJ_SECRETS, cors: true, timeoutSeconds: 540, maxInstances: 1 },
    async (req, res) => {
      const user = await requireAuth(req, res);
      if (!user) return;
      // Matches firestore.rules' isAdmin(): an `admin` custom claim on the
      // caller's ID token. Set it once with the Admin SDK's setCustomUserClaims.
      if (user.admin !== true) {
        return res.status(403).json({ success: false, message: "Forbidden" });
      }
      try {
        const summary = await catalogSync.runCatalogSync();
        logInfo("catalog_sync_run", { trigger: "manual", uid: user.uid, ...summary });
        res.status(200).json({ success: true, data: summary });
      } catch (err) {
        sendError(res, err, { endpoint: "runCatalogSync", uid: user.uid });
      }
    },
);

/**
 * Re-drives paid orders whose CJ push failed, and reclaims stale PUSHING
 * claims left by a timed-out invocation. This is the recovery path for the
 * most likely production failure - an empty CJ wallet, which fails every
 * order until it's topped up. Without it those orders stay paid and
 * unfulfilled forever, because the customer stops polling the moment they're
 * told the payment succeeded.
 */
exports.retryFailedFulfillments = onSchedule(
    // Single instance: two concurrent runs would re-drive the same orders.
    { schedule: "every 30 minutes", secrets: CJ_SECRETS, maxInstances: 1 },
    async () => {
      await orders.retryFailedFulfillments();
    },
);

/**
 * Pulls tracking for every order still in flight, so a customer opening the
 * app sees where their parcel is without having to trigger the lookup - and
 * so a delivery exception is noticed by us before they ask about it.
 */
exports.refreshOrderTracking = onSchedule(
    // Single instance: two concurrent runs would poll the same orders, and
    // the batch is chosen oldest-checked-first specifically so consecutive
    // runs move through the queue instead of repeating it.
    { schedule: "every 60 minutes", secrets: CJ_SECRETS, maxInstances: 1 },
    async () => {
      await orders.refreshTrackingBatch();
    },
);

module.exports.verifyAuth = verifyAuth;
