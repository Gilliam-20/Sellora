const axios = require("axios");
const { defineSecret } = require("firebase-functions/params");

// Set with: firebase functions:secrets:set INTASEND_SECRET_KEY
// (Dashboard -> API Settings -> Secret Key. Use the *test* secret key while
// in sandbox, the *live* one once you go live - they're different values.)
const INTASEND_SECRET_KEY = defineSecret("INTASEND_SECRET_KEY");

// Sandbox vs live is decided by which secret key you set (IntaSend keys are
// environment-scoped), and both hit the same api.intasend.com host - except
// sandbox testing can also be done at sandbox.intasend.com. We use the
// production host here since it works transparently with test keys too;
// switch to https://sandbox.intasend.com if you prefer the explicit sandbox host.
const INTASEND_BASE_URL = "https://api.intasend.com/api/v1";

// Safaricom caps a single M-Pesa STK push at KES 250,000 and rejects trivial
// amounts; IntaSend surfaces both as an opaque provider error, so we check
// first and tell the customer which other method to use instead.
const MPESA_MIN_KES = 10;
const MPESA_MAX_KES = 250000;

/**
 * @param {*} amount Order total in KES.
 * @return {string|null} A customer-facing reason M-Pesa can't take this
 *   amount, or null when it can.
 */
function mpesaAmountError(amount) {
  const value = Number(amount);
  if (!Number.isFinite(value) || value <= 0) {
    return "This order has no payable amount";
  }
  if (value < MPESA_MIN_KES) {
    return `M-Pesa payments start at KES ${MPESA_MIN_KES}`;
  }
  if (value > MPESA_MAX_KES) {
    return `M-Pesa cannot take more than KES ${MPESA_MAX_KES.toLocaleString("en-US")} ` +
      "in one payment - please pay by card or PayPal";
  }
  return null;
}

async function intasendRequest({ method = "POST", path, data }) {
  try {
    const res = await axios({
      method,
      url: `${INTASEND_BASE_URL}${path}`,
      data,
      headers: {
        "Authorization": `Bearer ${INTASEND_SECRET_KEY.value()}`,
        "Content-Type": "application/json",
      },
      timeout: 20000,
    });
    return res.data;
  } catch (err) {
    if (err.response) {
      throw new Error(
          `IntaSend ${path} failed (${err.response.status}): ${JSON.stringify(err.response.data)}`,
      );
    }
    throw err;
  }
}

/**
 * Triggers an M-Pesa STK push (payment prompt) directly to the customer's
 * phone. amount is in KES. phoneNumber format: 2547XXXXXXXX / 2541XXXXXXXX.
 * apiRef is your own order id - comes back to you in the webhook/status check.
 */
async function mpesaStkPush({ amount, phoneNumber, apiRef, email }) {
  const data = await intasendRequest({
    path: "/payment/mpesa-stk-push/",
    data: {
      amount: String(amount),
      phone_number: phoneNumber,
      api_ref: apiRef,
      email,
    },
  });
  // NOTE: verify the exact response shape against your sandbox call - IntaSend
  // nests the tracking id under `invoice` in most of their APIs. We defensively
  // check a couple of likely locations so this keeps working either way.
  const invoiceId = data.invoice?.invoice_id || data.id || data.invoice_id;
  return { raw: data, invoiceId };
}

/**
 * Creates a hosted checkout session for card or Google Pay payments.
 * Returns a URL you open in a WebView - the customer completes payment there,
 * then gets redirected back to redirectUrl.
 * method: 'CARD-PAYMENT' | 'GOOGLE-PAY'
 */
async function createCheckout({
  amount,
  currency = "KES",
  method,
  apiRef,
  email,
  firstName,
  lastName,
  phoneNumber,
  redirectUrl,
}) {
  const data = await intasendRequest({
    path: "/checkout/",
    data: {
      amount: String(amount),
      currency,
      method,
      api_ref: apiRef,
      email,
      first_name: firstName,
      last_name: lastName,
      phone_number: phoneNumber,
      redirect_url: redirectUrl,
      channel: "MOBILE",
    },
  });
  // NOTE: verify field name against your sandbox response (commonly `url`).
  const checkoutUrl = data.url || data.checkout_url;
  const checkoutId = data.id || data.checkout_id;
  return { raw: data, checkoutUrl, checkoutId };
}

/**
 * Authoritative payment status check - always call this server-side before
 * treating a payment as complete, whether triggered by polling or a webhook.
 * Pass whichever id you have (invoiceId from STK push, or checkoutId from checkout).
 */
async function checkPaymentStatus({ invoiceId, checkoutId }) {
  const data = await intasendRequest({
    path: "/payment/status/",
    data: {
      invoice_id: invoiceId,
      checkout_id: checkoutId,
    },
  });
  // Known states include PENDING, PROCESSING, COMPLETE, FAILED. Check the
  // `invoice.state` (or `state`) field on the raw response in your sandbox
  // and adjust isComplete()/isFailed() below if the field path differs.
  const state = (data.invoice?.state || data.state || "").toUpperCase();
  return { raw: data, state, isComplete: state === "COMPLETE", isFailed: state === "FAILED" };
}

/**
 * Pulls the paid amount/currency out of a payment-status response.
 * NOTE: like the state field above, these paths are IntaSend's documented
 * shape but unverified against a live response - confirm them in the sandbox.
 * Returns null when nothing recognizable is present so callers can tell
 * "amount doesn't match" apart from "couldn't read the amount".
 * @param {object} data Raw response from `checkPaymentStatus`.
 * @return {{value: number, currency: string}|null} The amount, or null.
 */
function extractAmount(data) {
  const invoice = data?.invoice || data || {};
  const raw = invoice.net_amount ?? invoice.value ?? invoice.amount;
  const value = Number(raw);
  const currency = invoice.currency || data?.currency;
  if (!Number.isFinite(value) || !currency) return null;
  return { value, currency: String(currency).toUpperCase() };
}

/**
 * Checks that IntaSend actually collected what we asked for. Defence in
 * depth only: the amount on an invoice is fixed by us at creation and the
 * payer can't alter it, so the real control is that the invoice belongs to
 * the order (see orders.paymentRefMatches). Returns true when the amount
 * can't be located rather than blocking a genuine payment on an unverified
 * field path - the caller logs that case.
 * @param {object} data Raw response from `checkPaymentStatus`.
 * @param {{amount: number, currency: string}} expected Our order's total.
 * @return {{ok: boolean, actual: (object|null)}} Verification outcome.
 */
function verifyAmount(data, { amount, currency }) {
  const actual = extractAmount(data);
  if (!actual) return { ok: true, actual: null };
  const ok = actual.currency === currency &&
      Math.abs(actual.value - amount) < 0.01;
  return { ok, actual };
}

// IntaSend only accepts a refund reason from a fixed list; anything else is
// rejected with a validation error. The free-text explanation goes in
// `reason_details`, which is what actually reaches our records.
const REFUND_REASONS = Object.freeze([
  "Duplicate",
  "Fraudulent",
  "Requested by customer",
  "Unavailable",
  "Other",
]);

/**
 * Coerces a reason to one IntaSend will accept.
 * @param {*} reason Caller-supplied reason.
 * @return {string} One of `REFUND_REASONS`.
 */
function normalizeRefundReason(reason) {
  const wanted = String(reason || "").trim().toLowerCase();
  return REFUND_REASONS.find((r) => r.toLowerCase() === wanted) || "Other";
}

/**
 * Refunds a completed IntaSend payment, in whole or in part.
 *
 * NOTE: like the rest of this file, the request/response field names are
 * IntaSend's documented shape and are unverified against a live account -
 * confirm them with a small sandbox refund before relying on this in anger
 * (TODO.md Phase 2). A refund that IntaSend rejects throws, and the caller
 * leaves the order untouched rather than recording a refund that never
 * happened.
 * @param {object} input Refund details.
 * @param {string} input.invoiceId The invoice to refund.
 * @param {number} input.amount Amount in KES.
 * @param {string=} input.reason One of `REFUND_REASONS`.
 * @param {string=} input.comment Free-text detail kept on the refund record.
 * @return {Promise<{raw: object, refundId: (string|null), status: string}>}
 *   IntaSend's response plus the fields we store.
 */
async function refundPayment({ invoiceId, amount, reason, comment }) {
  const data = await intasendRequest({
    path: "/payment/refund/",
    data: {
      invoice_id: invoiceId,
      amount: String(amount),
      reason: normalizeRefundReason(reason),
      reason_details: comment || "",
    },
  });
  return {
    raw: data,
    refundId: data?.refund_id || data?.id || data?.invoice?.invoice_id || null,
    status: String(data?.status || data?.state || "REQUESTED").toUpperCase(),
  };
}

module.exports = {
  mpesaStkPush,
  refundPayment,
  normalizeRefundReason,
  REFUND_REASONS,
  createCheckout,
  checkPaymentStatus,
  verifyAmount,
  mpesaAmountError,
  INTASEND_SECRET_KEY,
  MPESA_MIN_KES,
  MPESA_MAX_KES,
};
