import * as functions from 'firebase-functions';
import { defineSecret } from 'firebase-functions/params';
import axios from 'axios';
import { requireAuth } from './auth';

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

const cjEmail = defineSecret('CJ_EMAIL');
const cjPassword = defineSecret('CJ_PASSWORD');
const cjSecrets = { secrets: [cjEmail, cjPassword] };

async function getCjAccessToken(): Promise<string> {
  const { data } = await axios.post(`${CJ_BASE_URL}/authentication/getAccessToken`, {
    email: cjEmail.value(),
    password: cjPassword.value(),
  });
  return data.data.accessToken;
}

export const cjSearchProducts = functions.runWith(cjSecrets).https.onRequest(async (req, res) => {
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

export const cjProductDetail = functions.runWith(cjSecrets).https.onRequest(async (req, res) => {
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

export interface CjOrderRequest {
  cjProductId: string;
  quantity: number;
  shippingAddress: string;
  variant?: string;
}

/**
 * Places the real fulfillment order with CJ. Called two ways: directly,
 * in-process, by the IntaSend webhook once a payment is confirmed (see
 * intasend.ts) — no HTTP hop, no auth header needed, since that's a
 * server-to-server call within the same Functions runtime — and via the
 * `cjCreateOrder` HTTPS function below for manual/admin retry.
 */
export async function placeCjOrder(order: CjOrderRequest): Promise<{ cjOrderId?: string }> {
  const token = await getCjAccessToken();
  const { data } = await axios.post(
    `${CJ_BASE_URL}/shopping/order/createOrder`,
    {
      products: [{ vid: order.variant, pid: order.cjProductId, quantity: order.quantity }],
      shippingAddress: order.shippingAddress,
    },
    { headers: { 'CJ-Access-Token': token } },
  );
  return { cjOrderId: data.data?.orderId };
}

export const cjCreateOrder = functions.runWith(cjSecrets).https.onRequest(async (req, res) => {
  const user = await requireAuth(req, res);
  if (!user) return;

  try {
    const result = await placeCjOrder(req.body as CjOrderRequest);
    res.json(result);
  } catch (err: any) {
    functions.logger.error('cjCreateOrder failed', err?.response?.data ?? err.message);
    res.status(502).json({ message: 'Could not place the CJ Dropshipping order' });
  }
});

export const cjTrackShipment = functions.runWith(cjSecrets).https.onRequest(async (req, res) => {
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
