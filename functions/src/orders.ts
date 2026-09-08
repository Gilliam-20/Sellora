import * as functions from 'firebase-functions';
import axios from 'axios';
import { db } from './auth';

/**
 * Fires whenever a new order document is written (see
 * OrderRepository.placeOrder in the Flutter app). Real fulfillment
 * with CJ Dropshipping happens here — server-side, once — rather than
 * from the client, so a flaky connection or a malicious client can't
 * double-submit or skip payment verification.
 */
export const onOrderCreated = functions.firestore.document('orders/{orderId}').onCreate(async (snap, context) => {
  const order = snap.data();

  if (!order.paymentReference) {
    functions.logger.warn(`Order ${context.params.orderId} created with no payment reference — skipping fulfillment.`);
    return;
  }

  try {
    // In production: verify order.paymentReference against IntaSend's
    // status endpoint before forwarding to CJ (don't just trust the
    // client-set field). See intasend.ts's intasendStatus for the call.

    for (const item of order.items ?? []) {
      await axios.post(`${functions.config().app?.functions_base_url}/cjCreateOrder`, {
        cjProductId: item.productId,
        quantity: item.quantity,
        shippingAddress: order.shippingAddress,
        variant: item.variant,
      });
    }

    await snap.ref.update({ status: 'processing' });
  } catch (err) {
    functions.logger.error(`Fulfillment failed for order ${context.params.orderId}`, err);
    await snap.ref.update({ status: 'pending', fulfillmentError: true });
  }
});
