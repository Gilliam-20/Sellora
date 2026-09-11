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
exports.cjTrackShipment = exports.cjCreateOrder = exports.cjProductDetail = exports.cjSearchProducts = void 0;
exports.placeCjOrder = placeCjOrder;
const functions = __importStar(require("firebase-functions"));
const params_1 = require("firebase-functions/params");
const axios_1 = __importDefault(require("axios"));
const auth_1 = require("./auth");
/**
 * All CJ Dropshipping calls go through here so the CJ credentials never
 * ship inside the Flutter app. Set them once per environment with:
 *
 *   firebase functions:secrets:set CJ_EMAIL
 *   firebase functions:secrets:set CJ_PASSWORD
 *
 * See CJ Dropshipping's API docs for the exact auth handshake
 * (access-token request, then subsequent calls with CJ-Access-Token) —
 * this file sketches the shape; fill in the real endpoints/fields for
 * your CJ account type (CJ has both a public REST API and a
 * partner/API-key program).
 */
const CJ_BASE_URL = 'https://developers.cjdropshipping.com/api2.0/v1';
const cjEmail = (0, params_1.defineSecret)('CJ_EMAIL');
const cjPassword = (0, params_1.defineSecret)('CJ_PASSWORD');
const cjSecrets = { secrets: [cjEmail, cjPassword] };
async function getCjAccessToken() {
    const { data } = await axios_1.default.post(`${CJ_BASE_URL}/authentication/getAccessToken`, {
        email: cjEmail.value(),
        password: cjPassword.value(),
    });
    return data.data.accessToken;
}
exports.cjSearchProducts = functions.runWith(cjSecrets).https.onRequest(async (req, res) => {
    const user = await (0, auth_1.requireAuth)(req, res);
    if (!user)
        return;
    try {
        const token = await getCjAccessToken();
        const { keyword, category, page } = req.query;
        const { data } = await axios_1.default.get(`${CJ_BASE_URL}/product/list`, {
            headers: { 'CJ-Access-Token': token },
            params: { productName: keyword, categoryName: category, pageNum: page ?? 1, pageSize: 20 },
        });
        // Map CJ's response shape into Sellora's ProductModel shape.
        const products = (data.data?.list ?? []).map((p) => ({
            id: p.pid,
            cjProductId: p.pid,
            title: p.productNameEn,
            imageUrl: p.productImage,
            costPrice: Number(p.sellPrice ?? 0),
            sellPrice: Number(p.sellPrice ?? 0),
            currency: 'USD',
            category: p.categoryName ?? 'General',
            stock: p.stockNum ?? 0,
        }));
        res.json({ products });
    }
    catch (err) {
        functions.logger.error('cjSearchProducts failed', err?.response?.data ?? err.message);
        res.status(502).json({ message: 'Could not reach CJ Dropshipping' });
    }
});
exports.cjProductDetail = functions.runWith(cjSecrets).https.onRequest(async (req, res) => {
    const user = await (0, auth_1.requireAuth)(req, res);
    if (!user)
        return;
    try {
        const token = await getCjAccessToken();
        const { id } = req.query;
        const { data } = await axios_1.default.get(`${CJ_BASE_URL}/product/query`, {
            headers: { 'CJ-Access-Token': token },
            params: { pid: id },
        });
        res.json(data.data);
    }
    catch (err) {
        functions.logger.error('cjProductDetail failed', err?.response?.data ?? err.message);
        res.status(502).json({ message: 'Could not reach CJ Dropshipping' });
    }
});
/**
 * Places the real fulfillment order with CJ. Called two ways: directly,
 * in-process, by the IntaSend webhook once a payment is confirmed (see
 * intasend.ts) — no HTTP hop, no auth header needed, since that's a
 * server-to-server call within the same Functions runtime — and via the
 * `cjCreateOrder` HTTPS function below for manual/admin retry.
 */
async function placeCjOrder(order) {
    const token = await getCjAccessToken();
    const { data } = await axios_1.default.post(`${CJ_BASE_URL}/shopping/order/createOrder`, {
        products: [{ vid: order.variant, pid: order.cjProductId, quantity: order.quantity }],
        shippingAddress: order.shippingAddress,
    }, { headers: { 'CJ-Access-Token': token } });
    return { cjOrderId: data.data?.orderId };
}
exports.cjCreateOrder = functions.runWith(cjSecrets).https.onRequest(async (req, res) => {
    const user = await (0, auth_1.requireAuth)(req, res);
    if (!user)
        return;
    try {
        const result = await placeCjOrder(req.body);
        res.json(result);
    }
    catch (err) {
        functions.logger.error('cjCreateOrder failed', err?.response?.data ?? err.message);
        res.status(502).json({ message: 'Could not place the CJ Dropshipping order' });
    }
});
exports.cjTrackShipment = functions.runWith(cjSecrets).https.onRequest(async (req, res) => {
    const user = await (0, auth_1.requireAuth)(req, res);
    if (!user)
        return;
    try {
        const token = await getCjAccessToken();
        const { id } = req.query;
        const { data } = await axios_1.default.get(`${CJ_BASE_URL}/logistic/trackInfo`, {
            headers: { 'CJ-Access-Token': token },
            params: { orderId: id },
        });
        res.json({ status: data.data?.logisticStatus ?? 'processing' });
    }
    catch (err) {
        functions.logger.error('cjTrackShipment failed', err?.response?.data ?? err.message);
        res.status(502).json({ message: 'Could not reach CJ Dropshipping' });
    }
});
//# sourceMappingURL=cj.js.map