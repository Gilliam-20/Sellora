import * as functions from 'firebase-functions';
import { defineSecret } from 'firebase-functions/params';
import axios from 'axios';
import { requireAuth, db } from './auth';
import { placeCjOrder } from './cj';

/**
 * All IntaSend calls go through here so the secret key never ships inside
 * the Flutter app. Set them once per environment with:
 *
 *   firebase functions:secrets:set INTASEND_SECRET_KEY
 *   firebase functions:secrets:set INTASEND_WEBHOOK_CHALLENGE
 *
 * Use the sandbox host (sandbox.intasend.com) while testing, switch to
 * payment.intasend.com for production — see INTASEND_ENV below (a plain
 * runtime env var, not a secret, since it isn't sensitive).
 */
function intasendBaseUrl(): string {
  const env = process.env.INTASEND_ENV ?? 'sandbox';
  return env === 'live' ? 'https://payment.intasend.com/api/v1' : 'https://sandbox.intasend.com/api/v1';
}

const intasendSecretKey = defineSecret('INTASEND_SECRET_KEY');
const intasendWebhookChallenge = defineSecret('INTASEND_WEBHOOK_CHALLENGE');

function intasendHeaders() {
  return {
    Authorization: `Bearer ${intasendSecretKey.value()}`,
    'Content-Type': 'application/json',
  };
}

/** Triggers an M-Pesa STK push — used for both seller subscriptions and buyer checkout. */
export const intasendCollectMpesa = functions.runWith({ secrets: [intasendSecretKey] }).https.onRequest(async (req, res) => {
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
export const intasendCheckout = functions.runWith({ secrets: [intasendSecretKey] }).https.onRequest(async (req, res) => {
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
export const intasendStatus = functions.runWith({ secrets: [intasendSecretKey] }).https.onRequest(async (req, res) => {
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
 * IntaSend calls this webhook when a payment's state changes — the URL and
 * a shared "challenge" string are configured together in the IntaSend
 * dashboard, and IntaSend echoes that challenge back in every webhook
 * payload as `challenge` so you can confirm the call really came from
 * them. CONFIRM THIS AGAINST INTASEND'S CURRENT DOCS BEFORE GOING LIVE —
 * same caveat as cj.ts's auth handshake: this sketches the shape from
 * IntaSend's published webhook docs, not a verified test against a real
 * account.
 *
 * `api_ref` is the order id — see CheckoutController, which passes the
 * server-created order's id as the narrative/api_ref when it triggers
 * collectMpesa/createCheckout, precisely so this handler can find the
 * order again here.
 */
export const intasendWebhook = functions
  .runWith({ secrets: [intasendWebhookChallenge] })
  .https.onRequest(async (req, res) => {
    const body = req.body ?? {};

    if (body.challenge !== intasendWebhookChallenge.value()) {
      functions.logger.warn('IntaSend webhook received with a bad/missing challenge — rejecting.');
      res.status(401).send('invalid challenge');
      return;
    }

    const apiRef: string | undefined = body.api_ref ?? body.invoice?.api_ref;
    const state: string = (body.state ?? body.invoice?.state ?? '').toUpperCase();
    const invoiceId: string | undefined = body.invoice_id ?? body.invoice?.invoice_id;

    if (!apiRef) {
      functions.logger.warn('IntaSend webhook had no api_ref — nothing to reconcile.', body);
      res.status(200).send('ok');
      return;
    }

    const orderRef = db.collection('orders').doc(apiRef);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
      // Not every api_ref is an order — subscription billing_history
      // entries can also collect through IntaSend and aren't wired into
      // this webhook yet (see WORKLOG.md). Nothing to do here for those.
      functions.logger.info(`IntaSend webhook api_ref ${apiRef} does not match an order — ignoring.`);
      res.status(200).send('ok');
      return;
    }

    if (state === 'COMPLETE' || state === 'COMPLETED') {
      await orderRef.update({ paymentStatus: 'paid', paymentReference: invoiceId ?? apiRef });

      const order = orderSnap.data()!;
      try {
        for (const item of order.items ?? []) {
          await placeCjOrder({
            cjProductId: item.productId,
            quantity: item.quantity,
            shippingAddress: order.shippingAddress,
            variant: item.variant,
          });
        }
        await orderRef.update({ status: 'processing' });
      } catch (err) {
        functions.logger.error(`CJ fulfillment failed for order ${apiRef}`, err);
        await orderRef.update({ status: 'pending', fulfillmentError: true });
      }
    } else if (state === 'FAILED') {
      await orderRef.update({ paymentStatus: 'failed' });
    }

    res.status(200).send('ok');
  });
