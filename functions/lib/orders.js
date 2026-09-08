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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.onOrderCreated = void 0;
const functions = __importStar(require("firebase-functions"));
const axios_1 = __importDefault(require("axios"));
/**
 * Fires whenever a new order document is written (see
 * OrderRepository.placeOrder in the Flutter app). Real fulfillment
 * with CJ Dropshipping happens here — server-side, once — rather than
 * from the client, so a flaky connection or a malicious client can't
 * double-submit or skip payment verification.
 */
exports.onOrderCreated = functions.firestore.document('orders/{orderId}').onCreate(async (snap, context) => {
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
            await axios_1.default.post(`${functions.config().app?.functions_base_url}/cjCreateOrder`, {
                cjProductId: item.productId,
                quantity: item.quantity,
                shippingAddress: order.shippingAddress,
                variant: item.variant,
            });
        }
        await snap.ref.update({ status: 'processing' });
    }
    catch (err) {
        functions.logger.error(`Fulfillment failed for order ${context.params.orderId}`, err);
        await snap.ref.update({ status: 'pending', fulfillmentError: true });
    }
});
//# sourceMappingURL=orders.js.map