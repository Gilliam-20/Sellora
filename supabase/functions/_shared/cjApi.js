import { request } from "./http.js";
import { getValidAccessToken, CJ_BASE_URL } from "./cjAuth.js";
import { getPricing, retailProductPrice } from "./pricing.js";
import { withCache } from "./cache.js";

// Categories rarely change; search/detail carry live-ish prices so they get a
// much shorter TTL - just long enough to absorb repeat browsing/pagination.
const CATEGORY_CACHE_TTL_MS = 12 * 60 * 60 * 1000; // 12h
const SEARCH_CACHE_TTL_MS = 5 * 60 * 1000; // 5m
const DETAIL_CACHE_TTL_MS = 5 * 60 * 1000; // 5m
const VIDEO_CACHE_TTL_MS = 30 * 60 * 1000; // 30m - videos change far less than price/stock
const STOCK_CACHE_TTL_MS = 5 * 60 * 1000; // 5m - matches the detail TTL

/**
 * Low-level authenticated request to CJ's API.
 */
async function cjRequest({ method = "GET", path, params, data, extraHeaders }) {
  const accessToken = await getValidAccessToken();

  try {
    const res = await request({
      method,
      url: `${CJ_BASE_URL}${path}`,
      params,
      data,
      headers: {
        "CJ-Access-Token": accessToken,
        "Content-Type": "application/json",
        ...extraHeaders,
      },
      timeout: 15000,
    });

    // CJ convention: HTTP 200 + code 200 + result true = success.
    if (res.data.code !== 200 || res.data.result === false) {
      throw new Error(res.data.message || "CJ API returned an error");
    }
    return res.data.data;
  } catch (err) {
    if (err.response) {
      throw new Error(
          `CJ API ${path} failed (${err.response.status}): ${JSON.stringify(err.response.data)}`,
      );
    }
    throw err;
  }
}

/** Full category tree (first/second/third level). */
async function fetchCategories() {
  return withCache("categories", CATEGORY_CACHE_TTL_MS, () =>
    cjRequest({ path: "/product/getCategory" }));
}

/**
 * Paginated / searchable product list.
 * keyword, categoryId are optional filters; page/size control pagination.
 * regionKey (one of regions.js's `region` values) only steers which margin/
 * VAT tier prices this browse-time list for display - it's client-supplied
 * and never trusted for what checkout actually charges (orders.js re-derives
 * it from the shipping address instead).
 */
async function searchProducts({ keyword, categoryId, page = 1, size = 20, regionKey }) {
  const cacheKey =
      `search:${keyword || ""}:${categoryId || ""}:${page}:${size}:${regionKey || ""}`;
  return withCache(cacheKey, SEARCH_CACHE_TTL_MS, async () => {
    const params = { page, size };
    if (keyword) params.keyWord = keyword;
    if (categoryId) params.categoryId = categoryId;

    const data = await cjRequest({ path: "/product/listV2", params });

    const products = (data.content || []).flatMap((c) => c.productList || []);

    const pricing = await getPricing();
    return {
      page: data.pageNumber,
      size: data.pageSize,
      totalRecords: data.totalRecords,
      totalPages: data.totalPages,
      products: products.map(
          (product) => mapProductSummary(product, pricing, regionKey)),
    };
  });
}

function mapProductSummary(p, pricing, regionKey) {
  const supplierPriceUsd = toNumber(p.nowPrice ?? p.sellPrice) || 0;
  return {
    id: p.id,
    sku: p.sku,
    name: p.nameEn,
    image: p.bigImage,
    supplierPriceUsd,
    retailPriceUsd: retailProductPrice(
        supplierPriceUsd, pricing, { pid: p.id, categoryId: p.categoryId, regionKey }),
    categoryId: p.categoryId,
    categoryName: p.threeCategoryName,
  };
}

/**
 * Full product detail + all of its variants, merged into one response so the
 * app only needs a single call to render a product detail / variant picker
 * screen. See `searchProducts` for what `regionKey` does and doesn't affect.
 */
async function getProductDetail(pid, regionKey) {
  return withCache(`detail:${pid}:${regionKey || ""}`, DETAIL_CACHE_TTL_MS, async () => {
    const [product, variants, videos] = await Promise.all([
      cjRequest({ path: "/product/query", params: { pid } }),
      cjRequest({ path: "/product/variant/query", params: { pid } }),
      getProductVideos(pid),
    ]);

    const pricing = await getPricing();
    // CJ describes a variant only by a hyphen-joined value string
    // ("Black-XL"). The attribute *names* for those positions, when CJ sends
    // them at all, live on the product as a matching hyphen-joined string
    // ("Color-Size"), so the two have to be zipped back together.
    const attributeNames = splitCjKey(
        product.productKeyEn || product.productKey || "");
    return {
      id: product.pid,
      name: product.productNameEn,
      sku: product.productSku,
      image: product.bigImage,
      images: product.productImageSet || [],
      weight: toNumber(product.productWeight),
      categoryId: product.categoryId,
      categoryName: product.categoryName,
      description: product.description || product.descriptionEn || null,
      attributeNames,
      videos,
      variants: (variants || []).map((v) => ({
        vid: v.vid,
        name: v.variantNameEn,
        sku: v.variantSku,
        key: v.variantKey,
        attributes: variantAttributes(v.variantKey, attributeNames),
        image: v.variantImage || product.bigImage,
        supplierPriceUsd: toNumber(v.variantSellPrice),
        retailPriceUsd: retailProductPrice(
            toNumber(v.variantSellPrice) || 0,
            pricing,
            { pid: product.pid, categoryId: product.categoryId, regionKey },
        ),
        weight: toNumber(v.variantWeight),
      })),
    };
  });
}

/**
 * Playable videos for a product (empty array if it has none). CJ's video
 * links require a `Referer: https://developers.cjdropshipping.com/` header
 * on the actual playback request - the Flutter client attaches that itself
 * when it initializes the video player, this function just returns the URLs.
 */
async function getProductVideos(pid) {
  return withCache(`videos:${pid}`, VIDEO_CACHE_TTL_MS, async () => {
    let videos;
    try {
      videos = await cjRequest({
        method: "POST",
        path: "/product/queryVideosByProductId",
        data: { productId: pid },
      });
    } catch (err) {
      // Not every product has videos, and CJ returns an error rather than an
      // empty list in that case - treat any failure here as "no videos"
      // rather than failing the whole product detail response.
      console.warn(`getProductVideos(${pid}) failed: ${err.message}`);
      return [];
    }
    return (videos || [])
        .filter((v) => v.videoState === "ON_STATE")
        .map((v) => ({
          videoUrl: v.videoUrl,
          coverUrl: v.coverURL,
          name: v.videoName,
          duration: toNumber(v.duration),
        }));
  });
}

/**
 * Sellable inventory per variant for a product, summed across CJ's
 * warehouses.
 *
 * Returns null - meaning "unknown", not "none" - whenever the lookup fails or
 * comes back in a shape we can't read. Callers must fall back to their own
 * default in that case: writing zeros on a shape mismatch would mark the
 * whole catalog out of stock and make it unbuyable.
 * @param {string} pid CJ product id.
 * @return {Promise<Object<string, number>|null>} vid -> quantity, or null.
 */
async function getProductStock(pid) {
  return withCache(`stock:${pid}`, STOCK_CACHE_TTL_MS, async () => {
    let rows;
    try {
      rows = await cjRequest({
        path: "/product/stock/queryByPid",
        params: { pid },
      });
    } catch (err) {
      console.warn(`getProductStock(${pid}) failed: ${err.message}`);
      return null;
    }
    if (!Array.isArray(rows)) {
      console.warn(
          `getProductStock(${pid}): unexpected shape, not an array:`,
          JSON.stringify(rows).slice(0, 400));
      return null;
    }

    const byVid = {};
    for (const row of rows) {
      if (!row || typeof row !== "object") continue;
      const vid = row.vid || row.variantId;
      if (!vid) continue;
      // CJ names the quantity field differently across warehouse rows.
      const quantity = Number(
          row.storageNum ?? row.quantity ?? row.stock ?? row.num ?? 0);
      if (!Number.isFinite(quantity)) continue;
      byVid[vid] = (byVid[vid] || 0) + Math.max(0, quantity);
    }

    // A response we could parse but that shows stock nowhere is far more
    // likely a field-name mismatch than a product that is genuinely sold out
    // in every warehouse - and the cost of being wrong is an unbuyable
    // listing. Treat it as unknown and let the caller's default stand.
    if (Object.keys(byVid).length === 0 ||
        Object.values(byVid).every((q) => q === 0)) {
      console.warn(
          `getProductStock(${pid}): parsed no positive stock; treating as ` +
          "unknown. Confirm CJ's stock response field names.");
      return null;
    }
    return byVid;
  });
}

/**
 * Estimated shipping cost/time for a set of variants going to a destination country.
 * products: [{ vid: string, quantity: number }]
 */
async function calculateFreight({ startCountryCode = "CN", endCountryCode, products }) {
  return cjRequest({
    method: "POST",
    path: "/logistic/freightCalculate",
    data: { startCountryCode, endCountryCode, products },
  });
}

/** Single-variant lookup - cheaper than getProductDetail when you just need current price/weight for one vid. */
async function getVariant(vid) {
  const v = await cjRequest({ path: "/product/variant/queryByVid", params: { vid } });
  const pricing = await getPricing();
  return {
    vid: v.vid,
    pid: v.pid,
    name: v.variantNameEn,
    sku: v.variantSku,
    supplierPriceUsd: toNumber(v.variantSellPrice),
    // No categoryId available from CJ's single-variant lookup, so only a
    // product-level override applies here (see calculateProductPricing).
    retailPriceUsd: retailProductPrice(
        toNumber(v.variantSellPrice) || 0, pricing, { pid: v.pid }),
    weight: toNumber(v.variantWeight),
  };
}

/**
 * Pushes a paid order to CJ for fulfillment. This charges your CJ account
 * balance for the wholesale + shipping cost - it does NOT move the money
 * your customer paid you. Top up your CJ wallet balance separately in the
 * CJ dashboard; this call will fail with an insufficient-balance error if
 * you haven't.
 *
 * products: [{ vid, quantity, storeLineItemId }]
 */
async function createDropshipOrder({
  orderNumber,
  shippingAddress,
  products,
  logisticName,
  remark,
}) {
  const data = await cjRequest({
    method: "POST",
    path: "/shopping/order/createOrderV2",
    data: {
      orderNumber,
      shippingCountryCode: shippingAddress.countryCode,
      shippingCountry: shippingAddress.country,
      shippingProvince: shippingAddress.province,
      shippingCity: shippingAddress.city,
      shippingZip: shippingAddress.zip,
      shippingAddress: shippingAddress.line1,
      shippingAddress2: shippingAddress.line2 || "",
      shippingPhone: shippingAddress.phone,
      shippingCustomerName: shippingAddress.fullName,
      email: shippingAddress.email || "",
      remark: remark || "",
      fromCountryCode: "CN",
      logisticName: logisticName || undefined,
      // "platform" historically expects a known storefront value (e.g.
      // "shopify"); for a custom app it's fine to leave blank - confirm in
      // your CJ sandbox response / support if you hit a validation error here.
      platform: "",
      orderFlow: 1,
      products,
    },
    // platformToken can be empty for custom (non-Shopify/WooCommerce) integrations.
    extraHeaders: { platformToken: "" },
  });
  return data; // includes CJ's own orderId/orderNum on success
}

/**
 * CJ's own view of an order we pushed: its status and, once CJ hands the
 * parcel to a carrier, the tracking number.
 *
 * Deliberately uncached - this is the one CJ call whose whole purpose is to
 * return something different from last time. Polling is rationed by
 * `tracking.shouldRefreshTracking` instead, per order.
 * @param {string} cjOrderId CJ's order id, stored on the order as `cjOrderId`.
 * @return {Promise<object>} CJ's order detail payload.
 */
async function getOrderDetail(cjOrderId) {
  return cjRequest({
    path: "/shopping/order/getOrderDetail",
    params: { orderId: cjOrderId },
  });
}

/**
 * Carrier scans for a tracking number.
 *
 * Returns an empty list rather than throwing when CJ can't answer: a number
 * that no carrier has scanned yet is the normal state for a day or two after
 * dispatch, and CJ reports that as an error rather than an empty list. The
 * order's own status still renders without it.
 * @param {string} trackingNumber The carrier's number.
 * @return {Promise<Array<object>>} Raw tracking rows, newest order unspecified.
 */
async function getTrackInfo(trackingNumber) {
  let data;
  try {
    data = await cjRequest({
      path: "/logistic/getTrackInfo",
      params: { trackNumber: trackingNumber },
    });
  } catch (err) {
    console.warn(`getTrackInfo(${trackingNumber}) failed: ${err.message}`);
    return [];
  }
  // CJ returns either the rows themselves or an object wrapping them; the
  // key it wraps them under differs between its logistics endpoints.
  if (Array.isArray(data)) return data;
  const rows = data?.trackInfoList ?? data?.trackInfo ?? data?.list;
  if (Array.isArray(rows)) return rows;
  if (data) {
    console.warn(
        `getTrackInfo(${trackingNumber}): unexpected shape:`,
        JSON.stringify(data).slice(0, 400));
  }
  return [];
}

function toNumber(value) {
  const n = parseFloat(value);
  return Number.isNaN(n) ? null : n;
}

/**
 * Splits one of CJ's hyphen-joined key strings into its parts.
 * @param {string} key e.g. "Color-Size" or "Black-XL".
 * @return {Array<string>} Trimmed, non-empty parts.
 */
function splitCjKey(key) {
  return String(key || "")
      .split("-")
      .map((part) => part.trim())
      .filter(Boolean);
}

/**
 * Pairs a variant's values with the product's attribute names.
 *
 * Values can themselves contain a hyphen ("Navy-Blue"), which makes the split
 * ambiguous - so this only zips when the counts line up exactly. Otherwise it
 * falls back to a single "Option" attribute carrying the whole key, which
 * still gives the picker something selectable rather than nothing.
 * @param {string} variantKey CJ's variantKey, e.g. "Black-XL".
 * @param {Array<string>} attributeNames Names from the product, e.g.
 *   ["Color", "Size"].
 * @return {Object<string, string>} Attribute name -> value.
 */
function variantAttributes(variantKey, attributeNames) {
  const values = splitCjKey(variantKey);
  if (values.length === 0) return {};
  if (attributeNames.length !== values.length) {
    return { Option: String(variantKey || "").trim() };
  }
  return Object.fromEntries(
      attributeNames.map((name, index) => [name, values[index]]));
}

export {
  fetchCategories,
  searchProducts,
  getProductDetail,
  getProductVideos,
  getProductStock,
  getVariant,
  calculateFreight,
  createDropshipOrder,
  getOrderDetail,
  getTrackInfo,
  variantAttributes,
  splitCjKey,
};
