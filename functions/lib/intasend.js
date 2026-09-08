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
exports.intasendWebhook = exports.intasendStatus = exports.intasendCheckout = exports.intasendCollectMpesa = void 0;
const functions = __importStar(require("firebase-functions"));
const axios_1 = __importDefault(require("axios"));
const auth_1 = require("./auth");
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
function intasendBaseUrl() {
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
exports.intasendCollectMpesa = functions.https.onRequest(async (req, res) => {
    const user = await (0, auth_1.requireAuth)(req, res);
    if (!user)
        return;
    try {
        const { phone_number, amount, narrative } = req.body;
        const { data } = await axios_1.default.post(`${intasendBaseUrl()}/payment/mpesa-stk-push/`, {
            phone_number,
            amount,
            currency: 'KES',
            api_ref: narrative,
        }, { headers: intasendHeaders() });
        res.json(data);
    }
    catch (err) {
        functions.logger.error('intasendCollectMpesa failed', err?.response?.data ?? err.message);
        res.status(502).json({ message: 'M-Pesa payment could not be started' });
    }
});
/** Hosted checkout link for card payments (buyers/sellers outside Kenya). */
exports.intasendCheckout = functions.https.onRequest(async (req, res) => {
    const user = await (0, auth_1.requireAuth)(req, res);
    if (!user)
        return;
    try {
        const { amount, currency, email, narrative } = req.body;
        const { data } = await axios_1.default.post(`${intasendBaseUrl()}/checkout/`, {
            amount,
            currency,
            email,
            api_ref: narrative,
            redirect_url: 'https://your-app-domain.example/payment-complete',
        }, { headers: intasendHeaders() });
        res.json({ id: data.id, url: data.url });
    }
    catch (err) {
        functions.logger.error('intasendCheckout failed', err?.response?.data ?? err.message);
        res.status(502).json({ message: 'Checkout could not be created' });
    }
});
/** Polls the status of a previous collection/checkout request. */
exports.intasendStatus = functions.https.onRequest(async (req, res) => {
    const user = await (0, auth_1.requireAuth)(req, res);
    if (!user)
        return;
    try {
        const { reference } = req.query;
        const { data } = await axios_1.default.get(`${intasendBaseUrl()}/payment/status/${reference}/`, {
            headers: intasendHeaders(),
        });
        res.json({ state: data.invoice?.state ?? data.state });
    }
    catch (err) {
        functions.logger.error('intasendStatus failed', err?.response?.data ?? err.message);
        res.status(502).json({ message: 'Could not check payment status' });
    }
});
/**
 * IntaSend calls this webhook when a payment's state changes — configure
 * the URL in your IntaSend dashboard. Use it to confirm subscriptions
 * and orders server-side rather than trusting the client's "it worked".
 */
exports.intasendWebhook = functions.https.onRequest(async (req, res) => {
    functions.logger.info('IntaSend webhook received', req.body);
    // TODO: verify the webhook signature per IntaSend's docs, then:
    //  - if api_ref matches a subscription payment, mark it active in Firestore
    //  - if api_ref matches an order payment, flip the order from "awaiting
    //    payment" to "pending" and trigger cjCreateOrder (see orders.ts)
    res.status(200).send('ok');
});
//# sourceMappingURL=intasend.js.map