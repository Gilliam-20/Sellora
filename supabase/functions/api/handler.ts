// Sellora's backend: one Edge Function, routed by path
// (`/functions/v1/api/<endpoint>`), replacing the Firebase Cloud Functions in
// the old functions/ directory endpoint for endpoint. Same request bodies,
// same `{ success, data }` / `{ success: false, message }` envelope, so the
// app's services only changed their base URL (ApiEndpoints).
//
// verify_jwt is off for this function (supabase/config.toml): browsing and
// the IntaSend webhook are public, so each route authenticates itself -
// `requireUser` for signed-in routes, the admin check on top for admin
// routes, and the shared x-cron-secret for /cron/*. The CJ and IntaSend
// secret keys are only ever read here, server-side.

import * as cjApiModule from "../_shared/cjApi.js";
import * as intasendModule from "../_shared/intasendApi.js";
import * as ordersModule from "../_shared/orders.js";
import * as subscriptionsModule from "../_shared/subscriptions.js";
import * as refundsModule from "../_shared/refunds.js";
import * as catalogSyncModule from "../_shared/catalogSync.js";
import { refreshFxRates } from "../_shared/fx.js";
import { db } from "../_shared/db.js";
import { env } from "../_shared/env.js";
import { ALERTS, logAlert, logError, logInfo, logWarning } from "../_shared/logging.js";
import {
  clampPage,
  clampPageSize,
  isAllowedRedirectUrl,
  isValidMpesaPhone,
  sanitizeId,
  sanitizeKeyword,
  validateFreightRequest,
} from "../_shared/params.js";
import { publicError } from "../_shared/errors.js";
import { checkRateLimit } from "../_shared/rateLimit.js";

// deno-lint-ignore no-explicit-any
type Json = any;

// The shared modules are plain JS ported from functions/lib, where rows and
// provider payloads are loosely shaped by design; their JSDoc is
// documentation, not a contract, so they're used untyped from here.
const cjApi: Json = cjApiModule;
const intasend: Json = intasendModule;
const orders: Json = ordersModule;
const subscriptions: Json = subscriptionsModule;
const refunds: Json = refundsModule;
const catalogSync: Json = catalogSyncModule;

interface Caller {
  uid: string;
  email: string | undefined;
  admin: boolean;
}

interface Context {
  req: Request;
  query: URLSearchParams;
  body: Json;
}

type Route = (ctx: Context) => Promise<Response>;

// The Flutter web build calls from the browser, so every response - errors
// included - carries CORS headers, and preflights are answered directly.
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function json(status: number, body: Json, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json", ...headers },
  });
}

const ok = (data?: Json) => json(200, data === undefined ? { success: true } : { success: true, data });
const fail = (status: number, message: string, extra: Json = {}) =>
  json(status, { success: false, message, ...extra });

/**
 * Fails a request, recording which endpoint failed and for whose order - the
 * context that makes a payment failure debuggable from the logs alone.
 *
 * Only an `HttpError`'s message reaches the caller (see _shared/errors.js);
 * anything else - a CJ or IntaSend error body, a database error - is logged
 * in full here and answered with a generic 500.
 */
function sendError(err: unknown, context: Record<string, unknown> = {}): Response {
  const { status, message } = publicError(err as Error);
  if (status >= 500) {
    logError("request_failed", context, err);
  } else {
    logWarning("request_rejected", { ...context, status, reason: message });
  }
  return fail(status, message);
}

/**
 * The caller behind `Authorization: Bearer <Supabase access token>`, or
 * null. The token is checked with Supabase Auth itself (not just its
 * signature), so a deleted user's still-unexpired token is refused - the
 * Firebase version's `checkRevoked`. A banned user is refused too.
 */
export async function verifyAuth(req: Request): Promise<Caller | null> {
  const match = (req.headers.get("authorization") || "").match(/^Bearer (.+)$/);
  if (!match) return null;
  try {
    const { data, error } = await db().auth.getUser(match[1]);
    const user = data?.user;
    if (error || !user) return null;
    if (user.banned_until && Date.parse(user.banned_until) > Date.now()) return null;
    return {
      uid: user.id,
      email: user.email,
      // Only the service role can set app_metadata (grant-admin.js) - the
      // same source is_admin() reads in RLS.
      admin: user.app_metadata?.role === "admin",
    };
  } catch {
    return null;
  }
}

/** Wraps a handler that needs a signed-in caller (and optionally admin). */
function signedIn(
  handler: (ctx: Context, user: Caller) => Promise<Response>,
  { admin = false } = {},
): Route {
  return async (ctx) => {
    const user = await verifyAuth(ctx.req);
    if (!user) return fail(401, "Sign-in required");
    if (admin && !user.admin) return fail(403, "Forbidden");
    return handler(ctx, user);
  };
}

/**
 * Counts this call against the caller's per-user budget
 * (_shared/rateLimit.js), returning the 429 to send once it's spent.
 */
async function rateLimited(policy: string, uid: string): Promise<Response | null> {
  const { allowed, retryAfterMs } = await checkRateLimit(policy, uid);
  if (allowed) return null;
  logWarning("rate_limited", { policy, uid });
  return json(429, {
    success: false,
    message: "Too many requests. Please wait a moment and try again.",
  }, { "Retry-After": String(Math.max(1, Math.ceil(retryAfterMs / 1000))) });
}

/**
 * A payment provider's post-checkout redirect must point back at our own
 * app (see params.isAllowedRedirectUrl). Omitted is fine - the mobile app
 * sends none.
 */
function disallowedRedirect(urls: Record<string, unknown>): Response | null {
  for (const [name, value] of Object.entries(urls)) {
    if (value === undefined || value === null || value === "") continue;
    if (!isAllowedRedirectUrl(value)) return fail(400, `${name} is not an allowed URL`);
  }
  return null;
}

/**
 * Loads an order and checks the caller owns it. Ownership is always
 * re-checked server-side (the service role bypasses RLS), never trusted
 * from the client.
 */
async function loadOwnedOrder(
  orderId: unknown,
  uid: string,
): Promise<{ order?: Json; error?: Response }> {
  if (!sanitizeId(orderId)) return { error: fail(400, "A valid orderId is required") };
  const order = await orders.getOrder(orderId as string);
  if (order.buyerId !== uid) return { error: fail(403, "Forbidden") };
  return { order };
}

/**
 * Same as `loadOwnedOrder`, but additionally refuses an order that can't
 * accept a new payment attempt: one already paid, or one that already has a
 * live attempt with this same method. Both would otherwise leave the customer
 * charged twice - the second case because two STK prompts can sit on a phone
 * at once and only the latest invoice is the one we poll.
 */
async function loadPayableOrder(
  orderId: unknown,
  uid: string,
  paymentMethod: string,
): Promise<{ order?: Json; error?: Response }> {
  const loaded = await loadOwnedOrder(orderId, uid);
  if (loaded.error) return loaded;
  const order = loaded.order;
  if (!["pending", "awaiting_confirmation", "failed"].includes(order.paymentStatus)) {
    return { error: fail(409, "Order is already paid") };
  }
  if (orders.hasPendingAttempt(order, paymentMethod)) {
    return { error: fail(409, "A payment for this order is already in progress") };
  }
  return { order };
}

/** Loads a billing entry the caller owns that still accepts payment. */
async function loadPayableBillingEntry(
  entryId: unknown,
  uid: string,
): Promise<{ entry?: Json; error?: Response }> {
  if (!sanitizeId(entryId)) return { error: fail(400, "A valid billingEntryId is required") };
  const entry = await subscriptions.getBillingEntry(entryId as string);
  if (!entry || entry.sellerId !== uid) return { error: fail(403, "Forbidden") };
  if (!subscriptions.isPayable(entry)) {
    return { error: fail(409, "This billing entry is no longer payable") };
  }
  return { entry };
}

const MPESA_PHONE_MESSAGE =
  "phoneNumber must be a Kenyan M-Pesa number in the form 2547XXXXXXXX";
const HOSTED_METHODS = ["CARD-PAYMENT", "GOOGLE-PAY"];

// Refusal reasons from `refunds.decideRefund`, as something a support agent
// can act on rather than a code they have to look up.
const REFUND_REFUSALS: Record<string, string> = {
  not_paid: "This order was never paid, so there is nothing to refund",
  no_charge_to_refund: "This order has no recorded charge to refund",
  refund_in_progress: "A refund for this order is already being processed",
  already_refunded: "This order has already been fully refunded",
  invalid_amount: "The refund amount must be a positive number",
  exceeds_remaining: "That is more than the amount left to refund on this order",
};

// =============================================================================
// Catalog (public)
// =============================================================================

/** GET /getCategories - CJ's full category tree. */
const getCategories: Route = async () => {
  try {
    return ok(await cjApi.fetchCategories());
  } catch (err) {
    return sendError(err, { endpoint: "getCategories" });
  }
};

/**
 * GET /searchProducts?keyword=hoodie&categoryId=xxx&page=1&size=20
 *
 * Every parameter is clamped before it reaches CJ: this endpoint is public
 * and spends our one CJ API key, so an unbounded `size` or `page` is a way
 * to get that key rate-limited and take the catalog offline for everyone.
 */
const searchProducts: Route = async ({ query }) => {
  try {
    return ok(await cjApi.searchProducts({
      keyword: sanitizeKeyword(query.get("keyword") ?? undefined),
      categoryId: sanitizeId(query.get("categoryId") ?? undefined),
      page: clampPage(query.get("page") ?? undefined),
      size: clampPageSize(query.get("size") ?? undefined),
      regionKey: sanitizeId(query.get("region") ?? undefined),
    }));
  } catch (err) {
    return sendError(err, { endpoint: "searchProducts" });
  }
};

/** GET /getProductDetail?pid=xxxxxxxx - product info + all its variants. */
const getProductDetail: Route = async ({ query }) => {
  try {
    const pid = sanitizeId(query.get("pid") ?? undefined);
    if (!pid) return fail(400, "A valid pid is required");
    return ok(await cjApi.getProductDetail(pid, sanitizeId(query.get("region") ?? undefined)));
  } catch (err) {
    return sendError(err, { endpoint: "getProductDetail" });
  }
};

/**
 * POST /calculateFreight
 * body: { endCountryCode: "US", startCountryCode?: "CN", products: [{ vid, quantity }] }
 */
const calculateFreight = signedIn(async ({ body }, user) => {
  const limited = await rateLimited("calculateFreight", user.uid);
  if (limited) return limited;
  try {
    const request: Json = validateFreightRequest(body);
    if (request.error) return fail(400, request.error);
    return ok(await cjApi.calculateFreight(request.value));
  } catch (err) {
    return sendError(err, { endpoint: "calculateFreight", uid: user.uid });
  }
});

// =============================================================================
// Orders
// =============================================================================

/**
 * POST /createOrder
 * body: { items: [{ pid, vid, quantity }], shippingAddress: {...}, storeId,
 *   logisticName?: string }
 * Prices everything from CJ's live prices + the selling store's own listed
 * price. `logisticName` is the buyer's chosen CJ shipping line from
 * `calculateFreight` (omit it to auto-pick the cheapest) - only the name is
 * trusted, never a price.
 */
const createOrder = signedIn(async ({ body }, user) => {
  const limited = await rateLimited("createOrder", user.uid);
  if (limited) return limited;
  try {
    const { items, shippingAddress, logisticName, storeId } = body || {};
    const order = await orders.createOrder({
      uid: user.uid, items, shippingAddress, logisticName, storeId,
    });
    logInfo("order_created", {
      orderId: order.id,
      uid: user.uid,
      currency: order.currency,
      totalAmount: order.totalAmount,
    });
    return ok(order);
  } catch (err) {
    return sendError(err, { endpoint: "createOrder", uid: user.uid });
  }
});

/**
 * POST /getOrderTracking
 * body: { orderId, force?: boolean }
 * Refreshes the tracking snapshot from CJ when it's stale and returns it
 * either way. The app can read the same snapshot straight off the order row;
 * this endpoint exists to *refresh* it, since only the server may talk to CJ.
 */
const getOrderTracking = signedIn(async ({ body }, user) => {
  const limited = await rateLimited("orderTracking", user.uid);
  if (limited) return limited;
  try {
    const { orderId, force } = body || {};
    const { order, error } = await loadOwnedOrder(orderId, user.uid);
    if (error) return error;
    if (!order.cjOrderId) {
      // Paid but not yet with CJ, or a push that hasn't succeeded yet - a
      // normal state for a few minutes after checkout, not an error.
      return ok({
        tracking: null,
        status: order.status,
        cjOrderStatus: order.cjOrderStatus || "NOT_PUSHED",
        refreshed: false,
        reason: "not_pushed",
      });
    }
    const result = await orders.refreshOrderTracking(orderId, { force: force === true });
    return ok({
      tracking: result.tracking,
      status: result.status || order.status,
      cjOrderStatus: order.cjOrderStatus,
      refreshed: result.refreshed,
      reason: result.reason,
    });
  } catch (err) {
    return sendError(err, { endpoint: "getOrderTracking", uid: user.uid, orderId: body?.orderId });
  }
});

/**
 * POST /refundOrder   (admin only)
 * body: { orderId, amount?, reason?, comment? }
 * Refunds through the provider that took the payment and records it on the
 * order. Omitting `amount` refunds everything not already refunded. There is
 * no customer self-service refund - a request goes through support.
 */
const refundOrder = signedIn(async ({ body }, user) => {
  try {
    const { orderId, amount, reason, comment } = body || {};
    if (!sanitizeId(orderId)) return fail(400, "A valid orderId is required");
    const result = await refunds.refundOrder({
      orderId, amount, reason, comment, actorUid: user.uid,
    });
    if (!result.ok) {
      // A refusal is about the order's state, not a server fault: 409 for
      // "the order isn't in a state to be refunded", 400 for a bad amount.
      const status = result.reason === "invalid_amount" ||
          result.reason === "exceeds_remaining" ? 400 : 409;
      return fail(status, REFUND_REFUSALS[result.reason] || result.reason, {
        reason: result.reason,
      });
    }
    return ok(result);
  } catch (err) {
    return sendError(err, { endpoint: "refundOrder", uid: user.uid, orderId: body?.orderId });
  }
}, { admin: true });

// =============================================================================
// IntaSend - M-Pesa / Card / Google Pay
// =============================================================================

/**
 * POST /payOrderMpesa
 * body: { orderId, phoneNumber }   phoneNumber format: 2547XXXXXXXX
 * Triggers an STK push; the app then polls /confirmIntasendPayment (or the
 * webhook lands first).
 */
const payOrderMpesa = signedIn(async ({ body }, user) => {
  const limited = await rateLimited("mpesaPush", user.uid);
  if (limited) return limited;
  try {
    const { orderId, phoneNumber } = body || {};
    if (!isValidMpesaPhone(phoneNumber)) return fail(400, MPESA_PHONE_MESSAGE);
    const { order, error } = await loadPayableOrder(orderId, user.uid, "MPESA");
    if (error) return error;
    // M-Pesa has hard per-transaction limits. Checking here turns what would
    // be an opaque IntaSend error into an answer the customer can act on.
    const amountError = intasend.mpesaAmountError(order.totalKes);
    if (amountError) return fail(400, amountError);

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
    return ok({ invoiceId: result.invoiceId });
  } catch (err) {
    return sendError(err, { endpoint: "payOrderMpesa", uid: user.uid, orderId: body?.orderId });
  }
});

/**
 * POST /payOrderCard
 * body: { orderId, method, redirectUrl }   method: 'CARD-PAYMENT' | 'GOOGLE-PAY'
 * Returns a checkoutUrl for IntaSend's hosted page; call
 * /confirmIntasendPayment after it redirects back.
 */
const payOrderCard = signedIn(async ({ body }, user) => {
  const limited = await rateLimited("hostedCheckout", user.uid);
  if (limited) return limited;
  try {
    const { orderId, method, redirectUrl } = body || {};
    if (!HOSTED_METHODS.includes(method)) {
      return fail(400, "method must be CARD-PAYMENT or GOOGLE-PAY");
    }
    const badRedirect = disallowedRedirect({ redirectUrl });
    if (badRedirect) return badRedirect;
    const paymentMethod = method === "CARD-PAYMENT" ? "CARD" : "GOOGLE_PAY";
    const { order, error } = await loadPayableOrder(orderId, user.uid, paymentMethod);
    if (error) return error;

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
    return ok({ checkoutUrl: result.checkoutUrl });
  } catch (err) {
    return sendError(err, { endpoint: "payOrderCard", uid: user.uid, orderId: body?.orderId });
  }
});

/**
 * POST /confirmIntasendPayment
 * body: { orderId }
 * Re-checks payment status directly with IntaSend (never trusts the client),
 * and if complete, marks the order paid and pushes it to CJ.
 */
const confirmIntasendPayment = signedIn(async ({ body }, user) => {
  const limited = await rateLimited("confirmPayment", user.uid);
  if (limited) return limited;
  try {
    const { orderId } = body || {};
    const { order, error } = await loadOwnedOrder(orderId, user.uid);
    if (error) return error;
    if (!order.paymentRef?.invoiceId && !order.paymentRef?.checkoutId) {
      return fail(400, "No IntaSend payment has been started for this order");
    }

    const status = await intasend.checkPaymentStatus({
      invoiceId: order.paymentRef?.invoiceId,
      checkoutId: order.paymentRef?.checkoutId,
    });
    if (!status.isComplete) return ok({ paid: false, state: status.state });

    const check = intasend.verifyAmount(status.raw, { amount: order.totalKes, currency: "KES" });
    if (!check.ok) {
      logAlert(ALERTS.PAYMENT_AMOUNT_MISMATCH, {
        orderId,
        uid: user.uid,
        provider: "INTASEND",
        source: "confirmIntasendPayment",
        expected: { amount: order.totalKes, currency: "KES" },
        actual: check.actual,
      });
      return fail(409, "The amount paid does not match this order");
    }
    const result = await orders.fulfillOrder(orderId);
    return ok({ ...result, paid: true });
  } catch (err) {
    return sendError(err, {
      endpoint: "confirmIntasendPayment",
      uid: user.uid,
      orderId: body?.orderId,
    });
  }
});

/** Constant-time string comparison for shared secrets. */
function secretsMatch(a: unknown, b: string | undefined): boolean {
  if (typeof a !== "string" || !b || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/**
 * POST /intasendWebhook   (public - set this URL in the IntaSend dashboard)
 * The payload's own status is never trusted: the payment is re-verified with
 * checkPaymentStatus() before anything is fulfilled.
 *
 * Re-verifying the invoice is NOT on its own enough, because `invoice_id` and
 * `api_ref` arrive as two independent values on a public URL: pairing a
 * genuinely-completed invoice with someone else's orderId would otherwise
 * fulfill that order for free. So the invoice must also be one this order
 * actually started before it's allowed to pay for it.
 *
 * When the INTASEND_WEBHOOK_CHALLENGE secret is set, the payload's
 * `challenge` must match it too (IntaSend's dashboard lets you set one).
 */
const intasendWebhook: Route = async ({ body }) => {
  const payload = body || {};
  const orderId = payload.api_ref || payload.invoice?.api_ref;
  try {
    const expectedChallenge = env("INTASEND_WEBHOOK_CHALLENGE");
    if (expectedChallenge && !secretsMatch(payload.challenge, expectedChallenge)) {
      logAlert(ALERTS.WEBHOOK_SIGNATURE_INVALID, {
        provider: "INTASEND",
        reason: "challenge mismatch",
      });
      return fail(401, "Invalid challenge");
    }
    const invoiceId = payload.invoice_id || payload.invoice?.invoice_id;
    if (!invoiceId || !orderId || !sanitizeId(orderId)) {
      return fail(400, "Missing invoice_id/api_ref");
    }

    // api_ref addresses either an order or a pending subscription billing
    // entry. The billing lookup returns null rather than throwing for the
    // common case of an api_ref that is really an order id.
    const billingEntry = await subscriptions.getBillingEntry(orderId);
    if (billingEntry) {
      if (!subscriptions.isPayable(billingEntry)) {
        // Already handled - a webhook retry is a no-op.
        return ok({ paid: billingEntry.status === "paid" });
      }
      if (!subscriptions.billingRefMatches(billingEntry, { invoiceId })) {
        logAlert(ALERTS.WEBHOOK_SIGNATURE_INVALID, {
          provider: "INTASEND",
          billingEntryId: orderId,
          invoiceId,
          reason: "invoice was never started for this billing entry",
        });
        return json(200, { success: false, message: "Invoice does not belong to this billing entry" });
      }
      const billingStatus = await intasend.checkPaymentStatus({ invoiceId });
      if (!billingStatus.isComplete) return ok({ paid: false, state: billingStatus.state });
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
        return json(200, { success: false, message: "Amount mismatch" });
      }
      return ok(await subscriptions.activatePendingSubscription(orderId, {
        paymentReference: invoiceId,
      }));
    }

    const order = await orders.getOrder(orderId);
    if (!orders.paymentRefMatches(order, { invoiceId })) {
      logAlert(ALERTS.WEBHOOK_SIGNATURE_INVALID, {
        provider: "INTASEND",
        orderId,
        invoiceId,
        reason: "invoice was never started for this order",
      });
      return json(200, { success: false, message: "Invoice does not belong to this order" });
    }

    const status = await intasend.checkPaymentStatus({ invoiceId });
    if (!status.isComplete) return ok({ paid: false, state: status.state });

    const check = intasend.verifyAmount(status.raw, { amount: order.totalKes, currency: "KES" });
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
      return json(200, { success: false, message: "Amount mismatch" });
    }
    if (!check.actual) {
      logWarning("intasend_amount_unreadable", {
        orderId,
        invoiceId,
        note: "fulfilled on the invoice binding alone; confirm IntaSend's status response shape",
      });
    }
    return ok(await orders.fulfillOrder(orderId));
  } catch (err) {
    logError("request_failed", { endpoint: "intasendWebhook", orderId }, err);
    // Still ack with 200 so IntaSend doesn't hammer retries for a bug on our
    // side while we investigate; the order can be reconciled manually. This
    // URL is public, so the body carries the generic message, not err's.
    return json(200, { success: false, message: publicError(err as Error).message });
  }
};

// =============================================================================
// Subscriptions / Billing (seller plans)
// =============================================================================
//
// Mirrors the order-payment endpoints above, swapping an `orders` row for a
// `billing_history` row as the thing being paid for.

/**
 * POST /subscribeSeller
 * body: { planId }
 * Creates a pending billing_history entry, snapshotting the plan's price
 * server-side. Activates nothing - only a confirmed payment does.
 */
const subscribeSeller = signedIn(async ({ body }, user) => {
  const limited = await rateLimited("subscribe", user.uid);
  if (limited) return limited;
  try {
    const { planId } = body || {};
    if (!planId || typeof planId !== "string") return fail(400, "planId is required");
    return ok(await subscriptions.createBillingEntry({ sellerId: user.uid, planId }));
  } catch (err) {
    return sendError(err, { endpoint: "subscribeSeller", uid: user.uid });
  }
});

/** POST /payBillingMpesa  body: { billingEntryId, phoneNumber } */
const payBillingMpesa = signedIn(async ({ body }, user) => {
  const limited = await rateLimited("mpesaPush", user.uid);
  if (limited) return limited;
  try {
    const { billingEntryId, phoneNumber } = body || {};
    if (!isValidMpesaPhone(phoneNumber)) return fail(400, MPESA_PHONE_MESSAGE);
    const { entry, error } = await loadPayableBillingEntry(billingEntryId, user.uid);
    if (error) return error;
    const amountError = intasend.mpesaAmountError(entry.amountKes);
    if (amountError) return fail(400, amountError);

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
    return ok({ invoiceId: result.invoiceId });
  } catch (err) {
    return sendError(err, {
      endpoint: "payBillingMpesa",
      uid: user.uid,
      billingEntryId: body?.billingEntryId,
    });
  }
});

/** POST /payBillingCard  body: { billingEntryId, method, redirectUrl } */
const payBillingCard = signedIn(async ({ body }, user) => {
  const limited = await rateLimited("hostedCheckout", user.uid);
  if (limited) return limited;
  try {
    const { billingEntryId, method, redirectUrl } = body || {};
    if (!HOSTED_METHODS.includes(method)) {
      return fail(400, "method must be CARD-PAYMENT or GOOGLE-PAY");
    }
    const badRedirect = disallowedRedirect({ redirectUrl });
    if (badRedirect) return badRedirect;
    const { entry, error } = await loadPayableBillingEntry(billingEntryId, user.uid);
    if (error) return error;
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
    return ok({ checkoutUrl: result.checkoutUrl });
  } catch (err) {
    return sendError(err, {
      endpoint: "payBillingCard",
      uid: user.uid,
      billingEntryId: body?.billingEntryId,
    });
  }
});

/**
 * POST /confirmBillingPayment  body: { billingEntryId }
 * Re-checks payment status directly with IntaSend, and if complete,
 * activates the subscription.
 */
const confirmBillingPayment = signedIn(async ({ body }, user) => {
  const limited = await rateLimited("confirmPayment", user.uid);
  if (limited) return limited;
  try {
    const { billingEntryId } = body || {};
    if (!sanitizeId(billingEntryId)) return fail(400, "A valid billingEntryId is required");
    const entry = await subscriptions.getBillingEntry(billingEntryId);
    if (!entry || entry.sellerId !== user.uid) return fail(403, "Forbidden");
    if (!subscriptions.isPayable(entry)) return ok({ paid: entry.status === "paid" });
    if (!entry.paymentRef?.invoiceId && !entry.paymentRef?.checkoutId) {
      return fail(400, "No IntaSend payment has been started for this billing entry");
    }

    const status = await intasend.checkPaymentStatus({
      invoiceId: entry.paymentRef?.invoiceId,
      checkoutId: entry.paymentRef?.checkoutId,
    });
    if (!status.isComplete) return ok({ paid: false, state: status.state });

    const check = intasend.verifyAmount(status.raw, { amount: entry.amountKes, currency: "KES" });
    if (!check.ok) {
      logAlert(ALERTS.PAYMENT_AMOUNT_MISMATCH, {
        billingEntryId,
        uid: user.uid,
        provider: "INTASEND",
        source: "confirmBillingPayment",
        expected: { amount: entry.amountKes, currency: "KES" },
        actual: check.actual,
      });
      return fail(409, "The amount paid does not match this billing entry");
    }
    const result = await subscriptions.activatePendingSubscription(billingEntryId, {
      paymentReference: entry.paymentRef?.invoiceId || entry.paymentRef?.checkoutId,
    });
    return ok({ ...result, paid: true });
  } catch (err) {
    return sendError(err, {
      endpoint: "confirmBillingPayment",
      uid: user.uid,
      billingEntryId: body?.billingEntryId,
    });
  }
});

// =============================================================================
// Catalog sync + scheduled jobs
// =============================================================================

/**
 * POST /runCatalogSync   (admin only)
 * Same pass as the scheduled job, on demand - for seeding the catalog the
 * first time and after editing the 'catalog' app_config row.
 */
const runCatalogSync = signedIn(async (_ctx, user) => {
  try {
    const summary = await catalogSync.runCatalogSync();
    logInfo("catalog_sync_run", { trigger: "manual", uid: user.uid, ...summary });
    return ok(summary);
  } catch (err) {
    return sendError(err, { endpoint: "runCatalogSync", uid: user.uid });
  }
}, { admin: true });

// What pg_cron triggers (supabase/migrations/*_scheduled_jobs.sql).
const JOBS: Record<string, () => Promise<Json>> = {
  // A failure here is what makes rates go stale, and pricing refuses a rate
  // past its ceiling - so the failure is alerted, not just thrown.
  refreshFxRate: async () => {
    try {
      const doc = await refreshFxRates();
      return { rates: doc.rates };
    } catch (err) {
      logAlert(ALERTS.FX_STALE, { outcome: "refresh_failed" }, err as Error);
      throw err;
    }
  },
  syncCatalog: () => catalogSync.runCatalogSync(),
  // The recovery path for an empty CJ wallet or a CJ outage.
  retryFailedFulfillments: () => orders.retryFailedFulfillments(),
  refreshOrderTracking: () => orders.refreshTrackingBatch(),
};

/**
 * POST /cron/<job>   (x-cron-secret header required)
 * Answers 202 at once and finishes the job in the background, so pg_net's
 * request never times out on a long catalog sync.
 */
async function runJob(req: Request, job: string): Promise<Response> {
  if (!secretsMatch(req.headers.get("x-cron-secret"), env("CRON_SECRET"))) {
    return fail(401, "Unauthorized");
  }
  const run = JOBS[job];
  if (!run) return fail(404, "Unknown job");
  const work = run().then(
    (summary) => logInfo("scheduled_job_run", { job, ...summary }),
    (err) => logError("scheduled_job_failed", { job }, err),
  );
  // deno-lint-ignore no-explicit-any
  const runtime = (globalThis as any).EdgeRuntime;
  if (runtime?.waitUntil) {
    runtime.waitUntil(work);
  } else {
    await work;
  }
  return json(202, { success: true, data: { job, accepted: true } });
}

// =============================================================================
// Routing
// =============================================================================

const GET_ROUTES: Record<string, Route> = {
  getCategories,
  searchProducts,
  getProductDetail,
};

const POST_ROUTES: Record<string, Route> = {
  calculateFreight,
  createOrder,
  getOrderTracking,
  refundOrder,
  payOrderMpesa,
  payOrderCard,
  confirmIntasendPayment,
  intasendWebhook,
  subscribeSeller,
  payBillingMpesa,
  payBillingCard,
  confirmBillingPayment,
  runCatalogSync,
};

/** The route after `/api/` (`/functions/v1/api/x` arrives as `/api/x`). */
export function routeOf(pathname: string): string {
  const parts = pathname.split("/").filter(Boolean);
  const at = parts.indexOf("api");
  return (at >= 0 ? parts.slice(at + 1) : parts).join("/");
}

async function readBody(req: Request): Promise<Json> {
  const text = await req.text();
  if (!text) return {};
  const type = req.headers.get("content-type") || "";
  if (type.includes("application/x-www-form-urlencoded")) {
    return Object.fromEntries(new URLSearchParams(text));
  }
  return JSON.parse(text);
}

export async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  const url = new URL(req.url);
  const route = routeOf(url.pathname);

  // Reachability probe for the app's network manager: no auth, no work.
  if (route === "health") return json(200, { status: "ok" });
  if (route.startsWith("cron/")) {
    if (req.method !== "POST") return fail(405, "Use POST");
    return runJob(req, route.slice("cron/".length));
  }

  if (req.method === "GET" && GET_ROUTES[route]) {
    return GET_ROUTES[route]({ req, query: url.searchParams, body: {} });
  }
  if (POST_ROUTES[route]) {
    if (req.method !== "POST") return fail(405, "Use POST");
    let body: Json;
    try {
      body = await readBody(req);
    } catch {
      return fail(400, "Request body must be JSON");
    }
    return POST_ROUTES[route]({ req, query: url.searchParams, body });
  }
  if (GET_ROUTES[route]) return fail(405, "Use GET");
  return fail(404, "Not found");
}
