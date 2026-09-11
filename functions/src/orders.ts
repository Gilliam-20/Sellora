import * as functions from 'firebase-functions';
import { requireAuth, db } from './auth';

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

function orderCode(): string {
  return `SLR-${1000 + Math.floor(Math.random() * 9000)}`;
}

interface CreateOrderItemInput {
  productId: string;
  quantity: number;
  variant?: string;
}

/**
 * Creates an order server-side, re-pricing every item from its listing
 * document rather than trusting whatever total/fee/sellerId the client
 * sends — see CheckoutController, which now calls this (via
 * FirebaseOrderRepository.placeOrder) before ever contacting IntaSend, so
 * the returned order id can be used as the payment's api_ref (see
 * intasend.ts's intasendWebhook, which is what actually confirms payment
 * and kicks off CJ fulfillment — never this function).
 *
 * Assumes one seller per cart (see CheckoutController's own comment and
 * CLAUDE.md's "Known gaps") — a mixed-seller cart is rejected rather than
 * silently attributed to the wrong seller.
 */
export const createOrder = functions.https.onRequest(async (req, res) => {
  const user = await requireAuth(req, res);
  if (!user) return;

  try {
    const items = (req.body.items ?? []) as CreateOrderItemInput[];
    const { shippingAddress, storeId, paymentMethod, currency } = req.body;

    if (!Array.isArray(items) || items.length === 0) {
      res.status(400).json({ message: 'No items in order' });
      return;
    }
    if (!shippingAddress) {
      res.status(400).json({ message: 'shippingAddress is required' });
      return;
    }

    let subtotal = 0;
    let sellerId: string | null = null;
    const resolvedItems = [];

    for (const item of items) {
      const listingSnap = await db.collection('listings').doc(item.productId).get();
      if (!listingSnap.exists) {
        res.status(404).json({ message: `Listing ${item.productId} not found` });
        return;
      }
      const listing = listingSnap.data()!;
      if (sellerId === null) {
        sellerId = listing.sellerId ?? null;
      } else if (listing.sellerId !== sellerId) {
        res.status(400).json({ message: 'All items in an order must belong to the same seller' });
        return;
      }

      const quantity = Number(item.quantity) > 0 ? Number(item.quantity) : 1;
      const unitPrice = Number(listing.sellPrice ?? 0);
      subtotal += unitPrice * quantity;
      resolvedItems.push({
        productId: item.productId,
        title: listing.title ?? '',
        imageUrl: listing.imageUrl ?? '',
        quantity,
        unitPrice,
        variant: item.variant ?? null,
      });
    }

    if (!sellerId) {
      res.status(400).json({ message: 'Could not resolve a seller for this order' });
      return;
    }

    const serviceFeeRate = 0.02;
    const serviceFeeAmount = round2(subtotal * serviceFeeRate);
    const sellerRevenue = round2(subtotal - serviceFeeAmount);

    const orderRef = db.collection('orders').doc();
    const order = {
      id: orderRef.id,
      code: orderCode(),
      buyerId: user.uid,
      sellerId,
      storeId: storeId ?? null,
      items: resolvedItems,
      status: 'pending',
      total: round2(subtotal),
      currency: currency ?? 'KES',
      shippingAddress,
      paymentMethod: paymentMethod ?? 'IntaSend',
      paymentReference: null,
      trackingNumber: null,
      createdAt: new Date().toISOString(),
      paymentStatus: 'pending',
      serviceFeeRate,
      serviceFeeAmount,
      sellerRevenue,
      paymentFee: 0,
    };

    await orderRef.set(order);
    res.json({ orderId: orderRef.id, code: order.code, total: order.total, serviceFeeAmount });
  } catch (err: any) {
    functions.logger.error('createOrder failed', err?.message ?? err);
    res.status(500).json({ message: 'Could not create the order' });
  }
});
