"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.createOrder = void 0;
const functions = __importStar(require("firebase-functions"));
const auth_1 = require("./auth");
function round2(n) {
    return Math.round(n * 100) / 100;
}
function orderCode() {
    return `SLR-${1000 + Math.floor(Math.random() * 9000)}`;
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
exports.createOrder = functions.https.onRequest(async (req, res) => {
    const user = await (0, auth_1.requireAuth)(req, res);
    if (!user)
        return;
    try {
        const items = (req.body.items ?? []);
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
        let sellerId = null;
        const resolvedItems = [];
        for (const item of items) {
            const listingSnap = await auth_1.db.collection('listings').doc(item.productId).get();
            if (!listingSnap.exists) {
                res.status(404).json({ message: `Listing ${item.productId} not found` });
                return;
            }
            const listing = listingSnap.data();
            if (sellerId === null) {
                sellerId = listing.sellerId ?? null;
            }
            else if (listing.sellerId !== sellerId) {
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
        const orderRef = auth_1.db.collection('orders').doc();
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
    }
    catch (err) {
        functions.logger.error('createOrder failed', err?.message ?? err);
        res.status(500).json({ message: 'Could not create the order' });
    }
});
//# sourceMappingURL=orders.js.map