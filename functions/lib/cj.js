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
const functions = __importStar(require("firebase-functions"));
const axios_1 = __importDefault(require("axios"));
const auth_1 = require("./auth");
/**
 * All CJ Dropshipping calls go through here so the CJ API key/secret
 * (functions config: cj.api_key / cj.email / cj.password) never ships
 * inside the Flutter app. Set them with:
 *
 *   firebase functions:config:set cj.email="you@example.com" cj.password="..." cj.api_key="..."
 *
 * See CJ Dropshipping's API docs for the exact auth handshake
 * (access-token request, then subsequent calls with CJ-Access-Token) —
 * this file sketches the shape; fill in the real endpoints/fields for
 * your CJ account type (CJ has both a public REST API and a
 * partner/API-key program).
 */
const CJ_BASE_URL = 'https://developers.cjdropshipping.com/api2.0/v1';
async function getCjAccessToken() {
    const { email, password } = functions.config().cj ?? {};
    const { data } = await axios_1.default.post(`${CJ_BASE_URL}/authentication/getAccessToken`, { email, password });
    return data.data.accessToken;
}
exports.cjSearchProducts = functions.https.onRequest(async (req, res) => {
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
exports.cjProductDetail = functions.https.onRequest(async (req, res) => {
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
 * Places the real fulfillment order with CJ. In production this should
 * be called from a Firestore trigger once payment is confirmed (see
 * orders.ts), not directly from the client — exposed here as an
 * https function too for manual/admin retry.
 */
exports.cjCreateOrder = functions.https.onRequest(async (req, res) => {
    const user = await (0, auth_1.requireAuth)(req, res);
    if (!user)
        return;
    try {
        const token = await getCjAccessToken();
        const { cjProductId, quantity, shippingAddress, variant } = req.body;
        const { data } = await axios_1.default.post(`${CJ_BASE_URL}/shopping/order/createOrder`, {
            products: [{ vid: variant, pid: cjProductId, quantity }],
            shippingAddress,
        }, { headers: { 'CJ-Access-Token': token } });
        res.json({ cjOrderId: data.data?.orderId });
    }
    catch (err) {
        functions.logger.error('cjCreateOrder failed', err?.response?.data ?? err.message);
        res.status(502).json({ message: 'Could not place the CJ Dropshipping order' });
    }
});
exports.cjTrackShipment = functions.https.onRequest(async (req, res) => {
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