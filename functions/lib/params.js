/**
 * Validation for the query parameters of the public (unauthenticated) CJ
 * proxy endpoints.
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

module.exports = {
  clampInt,
  clampPage,
  clampPageSize,
  sanitizeKeyword,
  sanitizeId,
  MAX_PAGE,
  MAX_PAGE_SIZE,
  DEFAULT_PAGE_SIZE,
  MAX_KEYWORD_LENGTH,
};
