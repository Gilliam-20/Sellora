const axios = require("axios");
const { defineSecret } = require("firebase-functions/params");

// From your PayPal Developer Dashboard (developer.paypal.com) > Apps & Credentials.
// Use the Sandbox app's client id/secret while testing, Live app's once you go live.
const PAYPAL_CLIENT_ID = defineSecret("PAYPAL_CLIENT_ID");
const PAYPAL_CLIENT_SECRET = defineSecret("PAYPAL_CLIENT_SECRET");
// Created under Dashboard > Apps & Credentials > your app > Webhooks. Needed
// to verify that a webhook actually came from PayPal.
const PAYPAL_WEBHOOK_ID = defineSecret("PAYPAL_WEBHOOK_ID");

// Set PAYPAL_ENV=live (functions/.env locally, or the deployed function's
// environment) once you switch to Live app credentials. Defaults to sandbox
// so an unset environment can never accidentally charge real cards.
const PAYPAL_BASE_URL = process.env.PAYPAL_ENV === "live" ?
  "https://api-m.paypal.com" :
  "https://api-m.sandbox.paypal.com";

let cachedToken = null; // { accessToken, expiresAt } - simple per-instance cache

async function getAccessToken() {
  if (cachedToken && cachedToken.expiresAt - Date.now() > 60000) {
    return cachedToken.accessToken;
  }
  const basicAuth = Buffer.from(
      `${PAYPAL_CLIENT_ID.value()}:${PAYPAL_CLIENT_SECRET.value()}`,
  ).toString("base64");

  const res = await axios.post(
      `${PAYPAL_BASE_URL}/v1/oauth2/token`,
      "grant_type=client_credentials",
      {
        headers: {
          "Authorization": `Basic ${basicAuth}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
      },
  );
  cachedToken = {
    accessToken: res.data.access_token,
    expiresAt: Date.now() + res.data.expires_in * 1000,
  };
  return cachedToken.accessToken;
}

async function paypalRequest({ method = "POST", path, data }) {
  const token = await getAccessToken();
  try {
    const res = await axios({
      method,
      url: `${PAYPAL_BASE_URL}${path}`,
      data,
      headers: {
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      timeout: 20000,
    });
    return res.data;
  } catch (err) {
    if (err.response) {
      throw new Error(
          `PayPal ${path} failed (${err.response.status}): ${JSON.stringify(err.response.data)}`,
      );
    }
    throw err;
  }
}

/**
 * Creates a PayPal order for the given amount/currency (USD/EUR/GBP -
 * whatever the shopper's region resolved to server-side). referenceId
 * should be your Firestore orderId so you can match the webhook/capture
 * back to it. Returns the PayPal order id plus the "approve" link to open
 * in a WebView.
 */
async function createOrder({ amount, currency = "USD", referenceId, returnUrl, cancelUrl }) {
  const data = await paypalRequest({
    path: "/v2/checkout/orders",
    data: {
      intent: "CAPTURE",
      purchase_units: [
        {
          reference_id: referenceId,
          amount: { currency_code: currency, value: amount.toFixed(2) },
        },
      ],
      application_context: {
        return_url: returnUrl,
        cancel_url: cancelUrl,
        user_action: "PAY_NOW",
        shipping_preference: "NO_SHIPPING",
      },
    },
  });
  const approveUrl = (data.links || []).find((l) => l.rel === "approve")?.href;
  return { paypalOrderId: data.id, approveUrl, raw: data };
}

/**
 * Extracts the amount PayPal actually captured/quoted for the first
 * purchase unit, preferring the captured payment amount (present after
 * `captureOrder`) over the order-level amount.
 * @param {object} data Raw response from `captureOrder`/`getOrder`.
 * @return {{value: number, currency: string}|null} The amount, or null if
 *   the response doesn't carry a recognizable purchase unit amount.
 */
function extractAmount(data) {
  const unit = data?.purchase_units?.[0];
  const captured = unit?.payments?.captures?.[0]?.amount;
  const amount = captured || unit?.amount;
  if (!amount?.value || !amount?.currency_code) return null;
  return { value: Number(amount.value), currency: amount.currency_code };
}

/**
 * Checks that what PayPal actually charged matches what we expect (our own
 * order's amount/currency), not amount alone - a mismatched currency at the
 * same numeric value would otherwise slip through.
 * @param {object} data Raw response from `captureOrder`/`getOrder`.
 * @param {{amount: number, currency: string}} expected Our order's total.
 * @return {boolean} Whether the captured amount/currency match.
 */
function verifyAmount(data, { amount, currency }) {
  const actual = extractAmount(data);
  if (!actual) return false;
  return actual.currency === currency && Math.abs(actual.value - amount) < 0.01;
}

/**
 * Captures a previously-approved order. Call this after the buyer approves.
 *
 * PayPal rejects a second capture of the same order. That happens routinely
 * in normal operation, because our webhook and the client's return-from-
 * WebView race each other - so an already-captured order is resolved by
 * re-reading it rather than surfaced as a failure to a customer who has in
 * fact paid.
 * @param {string} paypalOrderId PayPal's order id.
 * @return {Promise<object>} `{ isCompleted, status, amount, raw }`.
 */
async function captureOrder(paypalOrderId) {
  try {
    const data = await paypalRequest({
      path: `/v2/checkout/orders/${paypalOrderId}/capture`,
      data: {},
    });
    const isCompleted = data.status === "COMPLETED";
    return { isCompleted, status: data.status, amount: extractAmount(data), raw: data };
  } catch (err) {
    if (!/ORDER_ALREADY_CAPTURED/.test(err.message)) throw err;
    const fresh = await getOrder(paypalOrderId);
    return {
      isCompleted: fresh.status === "COMPLETED",
      status: fresh.status,
      amount: extractAmount(fresh),
      raw: fresh,
      alreadyCaptured: true,
    };
  }
}

/**
 * The id of the capture a refund has to be issued against. PayPal refunds
 * are per-capture, not per-order, and this id only exists once the capture
 * has succeeded - which is why it's recorded onto the order at that point
 * (`orders.recordPaymentReference`) rather than looked up later.
 * @param {object} data Raw response from `captureOrder`/`getOrder`.
 * @return {string|null} The capture id, or null if the response has none.
 */
function extractCaptureId(data) {
  return data?.purchase_units?.[0]?.payments?.captures?.[0]?.id || null;
}

/**
 * Refunds a captured payment, in whole or in part.
 *
 * Omitting `amount` refunds the full capture, which is what PayPal treats as
 * the default; we always pass one so a partial refund and a full one take
 * exactly the same path.
 * @param {object} input Refund details.
 * @param {string} input.captureId The capture to refund.
 * @param {number} input.amount Amount in `currency`.
 * @param {string} input.currency ISO currency of the original capture.
 * @param {string=} input.note Shown to the payer on their PayPal statement.
 * @return {Promise<{raw: object, refundId: (string|null), status: string}>}
 *   PayPal's response plus the fields we store.
 */
async function refundCapture({ captureId, amount, currency, note }) {
  const data = await paypalRequest({
    path: `/v2/payments/captures/${captureId}/refund`,
    data: {
      amount: { value: Number(amount).toFixed(2), currency_code: currency },
      note_to_payer: note || undefined,
    },
  });
  return {
    raw: data,
    refundId: data?.id || null,
    status: String(data?.status || "PENDING").toUpperCase(),
  };
}

/** Fetches current order state without capturing - useful for a safe status poll. */
async function getOrder(paypalOrderId) {
  return paypalRequest({ method: "GET", path: `/v2/checkout/orders/${paypalOrderId}` });
}

/**
 * Verifies a webhook actually came from PayPal using PayPal's own verification
 * endpoint (simplest and most reliable option - no manual crypto needed).
 * `headers` must be the raw incoming request headers; `body` the parsed JSON body.
 */
async function verifyWebhookSignature(headers, body) {
  const data = await paypalRequest({
    path: "/v1/notifications/verify-webhook-signature",
    data: {
      auth_algo: headers["paypal-auth-algo"],
      cert_url: headers["paypal-cert-url"],
      transmission_id: headers["paypal-transmission-id"],
      transmission_sig: headers["paypal-transmission-sig"],
      transmission_time: headers["paypal-transmission-time"],
      webhook_id: PAYPAL_WEBHOOK_ID.value(),
      webhook_event: body,
    },
  });
  return data.verification_status === "SUCCESS";
}

module.exports = {
  createOrder,
  captureOrder,
  getOrder,
  refundCapture,
  extractCaptureId,
  verifyAmount,
  verifyWebhookSignature,
  PAYPAL_CLIENT_ID,
  PAYPAL_CLIENT_SECRET,
  PAYPAL_WEBHOOK_ID,
};
