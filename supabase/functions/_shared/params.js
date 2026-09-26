import { env } from "./env.js";

/**
 * Request validation: first the query parameters of the public
 * (unauthenticated) CJ proxy endpoints, then the bodies of the signed-in ones.
 *
 * These reach CJ's API on our single API key, so an unclamped `size` or an
 * arbitrarily long `keyword` is not just a big response - it's a way to get
 * that key rate-limited and take the whole catalog offline for everyone.
 */

// CJ's list endpoint pages at 20; 50 is comfortably above anything the app
// asks for and far below a scrape-sized page.
const MAX_PAGE_SIZE = 50;
const DEFAULT_PAGE_SIZE = 20;
// Deep paging is how you enumerate a catalog. The app never goes near this.
const MAX_PAGE = 100;
const MAX_KEYWORD_LENGTH = 64;
const MAX_ID_LENGTH = 64;

/**
 * @param {*} value Raw query value.
 * @param {number} fallback Value to use when it isn't a usable number.
 * @param {number} min Lower bound.
 * @param {number} max Upper bound.
 * @return {number} An integer within `[min, max]`.
 */
function clampInt(value, fallback, min, max) {
  // An absent or blank param means "not specified" - Number() would read both
  // as 0 and clamp them to the minimum, i.e. a one-product page.
  if (value === undefined || value === null || value === "") return fallback;
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(max, Math.max(min, Math.trunc(number)));
}

/**
 * @param {*} value Raw `page`.
 * @return {number} A page number within bounds.
 */
function clampPage(value) {
  return clampInt(value, 1, 1, MAX_PAGE);
}

/**
 * @param {*} value Raw `size`.
 * @return {number} A page size within bounds.
 */
function clampPageSize(value) {
  return clampInt(value, DEFAULT_PAGE_SIZE, 1, MAX_PAGE_SIZE);
}

/**
 * Normalizes a search keyword: trimmed, whitespace collapsed, length capped.
 * Normalizing also collapses the near-infinite set of keyword spellings an
 * attacker could use to miss the cache on every request.
 * @param {*} value Raw `keyword`.
 * @return {string} The normalized keyword, or "" if there isn't one.
 */
function sanitizeKeyword(value) {
  if (typeof value !== "string") return "";
  return value.trim().replace(/\s+/g, " ").slice(0, MAX_KEYWORD_LENGTH);
}

/**
 * Validates a CJ identifier (product id, variant id, category id).
 * @param {*} value Raw id.
 * @return {string|null} The id, or null if it isn't a plausible CJ id.
 */
function sanitizeId(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > MAX_ID_LENGTH) return null;
  return /^[A-Za-z0-9_-]+$/.test(trimmed) ? trimmed : null;
}

// ---------------------------------------------------------------------------
// Signed-in endpoint bodies. Signed-in isn't the same as trusted: anyone can
// create an account, so these are validated as strictly as the public ones.
// ---------------------------------------------------------------------------

// Same caps createOrder's validateOrderRequest applies to a cart, so a
// freight quote can never be asked for something checkout would refuse.
const MAX_FREIGHT_LINES = 50;
const MAX_LINE_QUANTITY = 20;

/**
 * @param {*} value Raw ISO 3166-1 alpha-2 code.
 * @return {string|null} The upper-cased code, or null if malformed.
 */
function sanitizeCountryCode(value) {
  if (typeof value !== "string") return null;
  const code = value.trim().toUpperCase();
  return /^[A-Z]{2}$/.test(code) ? code : null;
}

/**
 * Validates a /calculateFreight body. Unchecked, `products` went to CJ as
 * sent - an arbitrarily long array is one request that spends many CJ
 * quota units on our single key.
 * @param {object} body Raw request body.
 * @return {{error: string}|{value: object}} The clean request or why not.
 */
function validateFreightRequest(body) {
  const { endCountryCode, startCountryCode, products } = body || {};
  const end = sanitizeCountryCode(endCountryCode);
  if (!end) return { error: "A valid two-letter endCountryCode is required" };
  let start;
  if (startCountryCode !== undefined && startCountryCode !== null) {
    start = sanitizeCountryCode(startCountryCode);
    if (!start) return { error: "startCountryCode must be a two-letter country code" };
  }
  if (!Array.isArray(products) || products.length === 0 ||
      products.length > MAX_FREIGHT_LINES) {
    return { error: `products[] must contain between 1 and ${MAX_FREIGHT_LINES} items` };
  }
  const clean = [];
  for (const product of products) {
    const vid = sanitizeId(product?.vid);
    const quantity = product?.quantity;
    if (!vid) return { error: "Each product requires a valid vid" };
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > MAX_LINE_QUANTITY) {
      return { error: `Each quantity must be an integer between 1 and ${MAX_LINE_QUANTITY}` };
    }
    clean.push({ vid, quantity });
  }
  return { value: { endCountryCode: end, startCountryCode: start, products: clean } };
}

/**
 * IntaSend's STK push takes 2547XXXXXXXX / 2541XXXXXXXX - the same shape
 * lib/core/utils/validators.dart enforces client-side. Checked server-side
 * too so the endpoint can't be used to push payment prompts at arbitrary
 * numbers in arbitrary formats.
 * @param {*} value Raw phone number.
 * @return {boolean}
 */
function isValidMpesaPhone(value) {
  return typeof value === "string" && /^254[17]\d{8}$/.test(value);
}

// Where a hosted payment page may send the buyer afterwards. Unchecked, a
// caller could have IntaSend/PayPal - trusted, payment-branded pages -
// redirect to any site they like, which is a ready-made phishing hop.
const DEFAULT_REDIRECT_ORIGINS = [
  "https://sellora-20.web.app",
  "https://sellora-20.firebaseapp.com",
  "https://sellora.app",
  "https://www.sellora.app",
];

/**
 * @return {string[]} Allowed origins: `ALLOWED_REDIRECT_ORIGINS` (comma-
 *   separated secret) when set, otherwise the Firebase Hosting +
 *   sellora.app ones.
 */
function allowedRedirectOrigins() {
  const configured = (env("ALLOWED_REDIRECT_ORIGINS") || "")
      .split(",").map((o) => o.trim()).filter(Boolean);
  return configured.length ? configured : DEFAULT_REDIRECT_ORIGINS;
}

/**
 * @param {*} value Raw redirect/return/cancel URL.
 * @param {object=} options
 * @param {string[]=} options.origins Allowed origins (defaults as above).
 * @param {boolean=} options.allowLocalhost Also accept http://localhost -
 *   defaults to the ALLOW_LOCALHOST_REDIRECTS secret, for `flutter run`
 *   against `supabase functions serve`.
 * @return {boolean} Whether it's safe to hand to a payment provider.
 */
function isAllowedRedirectUrl(value, options = {}) {
  if (typeof value !== "string" || value.length > 2048) return false;
  let url;
  try {
    url = new URL(value);
  } catch {
    return false;
  }
  const allowLocalhost = options.allowLocalhost ??
    env("ALLOW_LOCALHOST_REDIRECTS") === "true";
  if (allowLocalhost && url.protocol === "http:" &&
      (url.hostname === "localhost" || url.hostname === "127.0.0.1")) {
    return true;
  }
  if (url.protocol !== "https:" || url.username || url.password) return false;
  return (options.origins || allowedRedirectOrigins()).includes(url.origin);
}

export {
  clampInt,
  clampPage,
  clampPageSize,
  sanitizeKeyword,
  sanitizeId,
  sanitizeCountryCode,
  validateFreightRequest,
  isValidMpesaPhone,
  isAllowedRedirectUrl,
  MAX_FREIGHT_LINES,
  MAX_PAGE,
  MAX_PAGE_SIZE,
  DEFAULT_PAGE_SIZE,
  MAX_KEYWORD_LENGTH,
};
