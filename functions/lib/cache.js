/**
 * Minimal in-memory LRU+TTL cache, scoped to a single warm function instance.
 * It won't be shared across cold starts or across the other instances that
 * `maxInstances` can spin up, but it's free (no extra Firestore reads/writes)
 * and still absorbs the repeat calls a busy instance sees for the same
 * category tree / search / product detail, keeping us further under CJ's
 * rate limit.
 *
 * The entry cap matters: search keys carry a caller-supplied keyword, so
 * without one a warm instance's memory grows with the number of distinct
 * keywords anyone cares to send, until the instance is OOM-killed.
 */
const store = new Map();

const MAX_ENTRIES = 500;

/** Returns the cached value for `key`, or undefined if missing/expired. */
function getCached(key) {
  const entry = store.get(key);
  if (!entry) return undefined;
  if (Date.now() > entry.expiresAt) {
    store.delete(key);
    return undefined;
  }
  // Re-insert so Map's insertion order doubles as the LRU order.
  store.delete(key);
  store.set(key, entry);
  return entry.value;
}

/** Stores `value` under `key` for `ttlMs` milliseconds. */
function setCached(key, value, ttlMs) {
  store.delete(key);
  store.set(key, { value, expiresAt: Date.now() + ttlMs });
  while (store.size > MAX_ENTRIES) {
    store.delete(store.keys().next().value);
  }
}

/**
 * Returns the cached value for `key`, or calls `fn`, caches its result for
 * `ttlMs` milliseconds, and returns it.
 * @param {string} key Cache key.
 * @param {number} ttlMs How long to keep the result, in milliseconds.
 * @param {function(): Promise<*>} fn Producer called on a cache miss.
 * @return {Promise<*>} The cached or freshly produced value.
 */
async function withCache(key, ttlMs, fn) {
  const cached = getCached(key);
  if (cached !== undefined) return cached;
  const value = await fn();
  setCached(key, value, ttlMs);
  return value;
}

/** Current entry count. For tests and diagnostics. */
function cacheSize() {
  return store.size;
}

/** Drops every entry. For tests. */
function clearCache() {
  store.clear();
}

module.exports = {
  getCached,
  setCached,
  withCache,
  cacheSize,
  clearCache,
  MAX_ENTRIES,
};
