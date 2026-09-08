import * as functions from 'firebase-functions';
import axios from 'axios';
import { requireAuth } from './auth';

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

async function getCjAccessToken(): Promise<string> {
  const { email, password } = functions.config().cj ?? {};
  const { data } = await axios.post(`${CJ_BASE_URL}/authentication/getAccessToken`, { email, password });
  return data.data.accessToken;
}

export const cjSearchProducts = functions.https.onRequest(async (req, res) => {
  const user = await requireAuth(req, res);
  if (!user) return;

  try {
    const token = await getCjAccessToken();
    const { keyword, category, page } = req.query;
    const { data } = await axios.get(`${CJ_BASE_URL}/product/list`, {
      headers: { 'CJ-Access-Token': token },
      params: { productName: keyword, categoryName: category, pageNum: page ?? 1, pageSize: 20 },
    });

    // Map CJ's response shape into Sellora's ProductModel shape.
    const products = (data.data?.list ?? []).map((p: any) => ({
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
  } catch (err: any) {
    functions.logger.error('cjSearchProducts failed', err?.response?.data ?? err.message);
    res.status(502).json({ message: 'Could not reach CJ Dropshipping' });
  }
});

export const cjProductDetail = functions.https.onRequest(async (req, res) => {
  const user = await requireAuth(req, res);
  if (!user) return;

  try {
    const token = await getCjAccessToken();
    const { id } = req.query;
    const { data } = await axios.get(`${CJ_BASE_URL}/product/query`, {
      headers: { 'CJ-Access-Token': token },
      params: { pid: id },
    });
    res.json(data.data);
  } catch (err: any) {
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
export const cjCreateOrder = functions.https.onRequest(async (req, res) => {
  const user = await requireAuth(req, res);
  if (!user) return;

  try {
    const token = await getCjAccessToken();
    const { cjProductId, quantity, shippingAddress, variant } = req.body;
    const { data } = await axios.post(
      `${CJ_BASE_URL}/shopping/order/createOrder`,
      {
        products: [{ vid: variant, pid: cjProductId, quantity }],
        shippingAddress,
      },
      { headers: { 'CJ-Access-Token': token } },
    );
    res.json({ cjOrderId: data.data?.orderId });
  } catch (err: any) {
    functions.logger.error('cjCreateOrder failed', err?.response?.data ?? err.message);
    res.status(502).json({ message: 'Could not place the CJ Dropshipping order' });
  }
});

export const cjTrackShipment = functions.https.onRequest(async (req, res) => {
  const user = await requireAuth(req, res);
  if (!user) return;

  try {
    const token = await getCjAccessToken();
    const { id } = req.query;
    const { data } = await axios.get(`${CJ_BASE_URL}/logistic/trackInfo`, {
      headers: { 'CJ-Access-Token': token },
      params: { orderId: id },
    });
    res.json({ status: data.data?.logisticStatus ?? 'processing' });
  } catch (err: any) {
    functions.logger.error('cjTrackShipment failed', err?.response?.data ?? err.message);
    res.status(502).json({ message: 'Could not reach CJ Dropshipping' });
  }
});
