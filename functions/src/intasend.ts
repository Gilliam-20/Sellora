import * as functions from 'firebase-functions';
import axios from 'axios';
import { requireAuth } from './auth';

/**
 * All IntaSend calls go through here so the secret key
 * (functions config: intasend.secret_key / intasend.publishable_key)
 * never ships inside the Flutter app.
 *
 *   firebase functions:config:set intasend.secret_key="ISSecretKey_..." intasend.publishable_key="ISPubKey_..."
 *
 * Use the sandbox host (sandbox.intasend.com) while testing, switch to
 * payment.intasend.com for production — see functions:config:set
 * intasend.env="sandbox" | "live".
 */
function intasendBaseUrl(): string {
  const env = functions.config().intasend?.env ?? 'sandbox';
  return env === 'live' ? 'https://payment.intasend.com/api/v1' : 'https://sandbox.intasend.com/api/v1';
}

function intasendHeaders() {
  const secretKey = functions.config().intasend?.secret_key;
  return {
    Authorization: `Bearer ${secretKey}`,
    'Content-Type': 'application/json',
  };
}

/** Triggers an M-Pesa STK push — used for both seller subscriptions and buyer checkout. */
export const intasendCollectMpesa = functions.https.onRequest(async (req, res) => {
  const user = await requireAuth(req, res);
  if (!user) return;

  try {
    const { phone_number, amount, narrative } = req.body;
    const { data } = await axios.post(
      `${intasendBaseUrl()}/payment/mpesa-stk-push/`,
      {
        phone_number,
        amount,
        currency: 'KES',
        api_ref: narrative,
      },
      { headers: intasendHeaders() },
    );
    res.json(data);
  } catch (err: any) {
    functions.logger.error('intasendCollectMpesa failed', err?.response?.data ?? err.message);
    res.status(502).json({ message: 'M-Pesa payment could not be started' });
  }
});

/** Hosted checkout link for card payments (buyers/sellers outside Kenya). */
export const intasendCheckout = functions.https.onRequest(async (req, res) => {
  const user = await requireAuth(req, res);
  if (!user) return;

  try {
    const { amount, currency, email, narrative } = req.body;
    const { data } = await axios.post(
      `${intasendBaseUrl()}/checkout/`,
      {
        amount,
        currency,
        email,
        api_ref: narrative,
        redirect_url: 'https://your-app-domain.example/payment-complete',
      },
      { headers: intasendHeaders() },
    );
    res.json({ id: data.id, url: data.url });
  } catch (err: any) {
    functions.logger.error('intasendCheckout failed', err?.response?.data ?? err.message);
    res.status(502).json({ message: 'Checkout could not be created' });
  }
});

/** Polls the status of a previous collection/checkout request. */
export const intasendStatus = functions.https.onRequest(async (req, res) => {
  const user = await requireAuth(req, res);
  if (!user) return;

  try {
    const { reference } = req.query;
    const { data } = await axios.get(`${intasendBaseUrl()}/payment/status/${reference}/`, {
      headers: intasendHeaders(),
    });
    res.json({ state: data.invoice?.state ?? data.state });
  } catch (err: any) {
    functions.logger.error('intasendStatus failed', err?.response?.data ?? err.message);
    res.status(502).json({ message: 'Could not check payment status' });
  }
});

/**
 * IntaSend calls this webhook when a payment's state changes — configure
 * the URL in your IntaSend dashboard. Use it to confirm subscriptions
 * and orders server-side rather than trusting the client's "it worked".
 */
export const intasendWebhook = functions.https.onRequest(async (req, res) => {
  functions.logger.info('IntaSend webhook received', req.body);
  // TODO: verify the webhook signature per IntaSend's docs, then:
  //  - if api_ref matches a subscription payment, mark it active in Firestore
  //  - if api_ref matches an order payment, flip the order from "awaiting
  //    payment" to "pending" and trigger cjCreateOrder (see orders.ts)
  res.status(200).send('ok');
});
