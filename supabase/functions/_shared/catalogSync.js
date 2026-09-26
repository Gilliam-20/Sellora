import { db, must } from "./db.js";
import * as cjApi from "./cjApi.js";
import { toRow } from "./rows.js";

// The shared browse catalog. Was the top-level Firestore `products` and
// `categories` collections; the tenant-owned listings are `products`.
const PRODUCTS = "catalog_products";
const CATEGORIES = "catalog_categories";

// CJ rate-limits its API, and a sync is the one place we make many calls in a
// row, so every CJ round-trip is spaced out. Catalog freshness is measured in
// hours - there is nothing to gain from hammering it.
const CJ_CALL_SPACING_MS = 400;

// Rows per upsert/select round trip - keeps each request body and URL
// (an `in` filter) comfortably small.
const BATCH_LIMIT = 200;

const defaults = Object.freeze({
  // Each source is either { categoryId } or { keyword }, plus an optional
  // `limit` (how many products to carry from it) and `featured` flag.
  sources: [],
  // Pinned to the home feed in array order, ahead of any `featured` source.
  featuredProductIds: [],
  // Never carried, whatever a source returns.
  blockedProductIds: [],
  // Ceiling on how many products one run will write, so a misconfigured
  // source can't run away with the CJ rate limit.
  maxProductsPerRun: 300,
  // Detail (variants/images/description) costs one extra CJ call per product,
  // so it's filled in progressively rather than for the whole catalog at once.
  // Products missing detail are picked up on subsequent runs. Kept well
  // inside an Edge Function's wall-clock limit (150s on the free plan): each
  // one is several paced CJ calls.
  maxDetailCallsPerRun: 20,
  // CJ's catalog API doesn't report inventory, so we can't know real stock
  // here. Until the CJ stock endpoint is wired up, carried products are
  // treated as available - writing 0 would mark the entire catalog
  // out-of-stock and make it unbuyable.
  assumedStock: 999,
  syncCategories: true,
});

/** @return {Promise<void>} Resolves after the CJ pacing interval. */
function pace() {
  return new Promise((resolve) => setTimeout(resolve, CJ_CALL_SPACING_MS));
}

/**
 * Reads the `app_config` row 'catalog', falling back to `defaults` for
 * anything missing.
 * @return {Promise<object>} The resolved catalog config.
 */
async function getCatalogConfig() {
  const row = must(await db().from("app_config")
      .select("value").eq("key", "catalog").maybeSingle());
  const source = row?.value || {};
  const positiveInt = (value, fallback) => {
    const n = Number(value);
    return Number.isInteger(n) && n > 0 ? n : fallback;
  };
  return {
    sources: Array.isArray(source.sources) ? source.sources : defaults.sources,
    featuredProductIds: Array.isArray(source.featuredProductIds) ?
      source.featuredProductIds.map(String) : defaults.featuredProductIds,
    blockedProductIds: new Set(
        (Array.isArray(source.blockedProductIds) ?
          source.blockedProductIds : []).map(String)),
    maxProductsPerRun: positiveInt(
        source.maxProductsPerRun, defaults.maxProductsPerRun),
    maxDetailCallsPerRun: positiveInt(
        source.maxDetailCallsPerRun, defaults.maxDetailCallsPerRun),
    assumedStock: positiveInt(source.assumedStock, defaults.assumedStock),
    syncCategories: source.syncCategories !== false,
  };
}

// ---------------------------------------------------------------------------
// Categories
// ---------------------------------------------------------------------------

/**
 * CJ nests its category tree three levels deep and names the id/name/children
 * keys differently at each level. Rather than hard-code those names - they're
 * the part of CJ's contract most likely to differ from the docs - this walks
 * whatever shape comes back, matching on key *suffix*.
 * @param {*} node A node from CJ's category response.
 * @return {{id: string, name: string, children: Array}|null} Normalized node.
 */
function normalizeCategoryNode(node) {
  if (!node || typeof node !== "object") return null;
  let id = null;
  let name = null;
  let children = [];
  for (const [key, value] of Object.entries(node)) {
    const k = key.toLowerCase();
    if (Array.isArray(value)) {
      if (k.includes("list") || k.includes("children")) children = value;
      continue;
    }
    if (id === null && k.endsWith("id") && value) id = String(value);
    if (name === null && k.endsWith("name") && value) name = String(value);
  }
  if (!id || !name) return null;
  return { id, name, children };
}

/**
 * Flattens CJ's nested tree into `{ id, name, parentId, level }` rows.
 * @param {Array} nodes Raw CJ nodes.
 * @param {string} parentId Parent category id ("" at the top level).
 * @param {number} level Depth, starting at 0.
 * @param {Array} out Accumulator.
 * @return {Array<object>} Flattened rows.
 */
function flattenCategories(nodes, parentId = "", level = 0, out = []) {
  if (!Array.isArray(nodes)) return out;
  for (const raw of nodes) {
    const node = normalizeCategoryNode(raw);
    if (!node) continue;
    out.push({ id: node.id, name: node.name, parentId, level });
    flattenCategories(node.children, node.id, level + 1, out);
  }
  return out;
}

/**
 * Mirrors CJ's category tree into `catalog_categories`.
 * @return {Promise<object>} Counts for logging.
 */
async function syncCategories() {
  const tree = await cjApi.fetchCategories();
  const rows = flattenCategories(tree);
  if (rows.length === 0) {
    // Almost certainly a shape mismatch rather than an empty CJ catalog -
    // log enough to fix the mapper without a redeploy to add logging.
    console.error(
        "syncCategories: CJ returned a tree we couldn't flatten. First node:",
        JSON.stringify(Array.isArray(tree) ? tree[0] : tree).slice(0, 800));
    return { written: 0 };
  }

  let written = 0;
  const now = new Date().toISOString();
  for (let i = 0; i < rows.length; i += BATCH_LIMIT) {
    const batch = rows.slice(i, i + BATCH_LIMIT).map((row, offset) => toRow({
      id: row.id,
      name: row.name,
      parentId: row.parentId,
      level: row.level,
      // Clients order by sortOrder; tree order is the best default and an
      // admin can override any individual row afterwards.
      sortOrder: i + offset,
      isActive: true,
      isFeatured: row.level === 0,
      source: "cj",
      updatedAt: now,
    }));
    must(await db().from(CATEGORIES).upsert(batch));
    written += batch.length;
  }
  return { written };
}

// ---------------------------------------------------------------------------
// Products
// ---------------------------------------------------------------------------

/**
 * Pages a single configured source until it has `limit` products.
 * @param {object} source `{ categoryId?, keyword?, limit? }`.
 * @param {number} ceiling Hard cap left in this run's budget.
 * @return {Promise<Array<object>>} CJ product summaries.
 */
async function collectFromSource(source, ceiling) {
  const limit = Math.min(Number(source.limit) || 40, ceiling);
  const collected = [];
  const size = 20;
  for (let page = 1; collected.length < limit; page++) {
    const result = await cjApi.searchProducts({
      keyword: source.keyword,
      categoryId: source.categoryId,
      page,
      size,
    });
    const products = result?.products || [];
    collected.push(...products);
    if (products.length < size) break; // last page
    await pace();
  }
  return collected.slice(0, limit);
}

/**
 * Maps a CJ product summary onto a `catalog_products` row (camelCase here,
 * translated by `toRow` at write time).
 * @param {object} product CJ summary from `searchProducts`.
 * @param {object} config Catalog config.
 * @return {object} Row fields.
 */
function mapSummary(product, config) {
  return {
    title: product.name || "",
    sku: product.sku || "",
    thumbnailUrl: product.image || "",
    // `retailPriceUsd` is what pricing.js already marked the supplier cost up
    // to, so the client renders a sell price without repeating the math.
    priceMin: Number(product.retailPriceUsd) || 0,
    // No CJ concept of a "was" price, so there is no markdown to show.
    compareAtPriceMin: 0,
    supplierPriceUsd: Number(product.supplierPriceUsd) || 0,
    primaryCategoryId: product.categoryId || "",
    categoryName: product.categoryName || "",
    productType: "cj",
    stockAvailable: config.assumedStock,
    source: "cj",
    cjProductId: String(product.id),
    isActive: true,
  };
}

/**
 * Enriches a catalog product with the fields only CJ's detail endpoint
 * carries: full image set, description, variants and videos.
 * @param {string} pid CJ product id.
 * @param {object} config Catalog config.
 * @return {Promise<object|null>} Extra row fields, or null on failure.
 */
async function fetchDetailFields(pid, config) {
  let detail;
  try {
    detail = await cjApi.getProductDetail(pid);
  } catch (err) {
    console.warn(`catalogSync: detail fetch failed for ${pid}:`, err.message);
    return null;
  }
  // null means CJ's inventory lookup failed or came back unreadable, which is
  // not the same as zero - fall back to the configured default rather than
  // publishing an unbuyable product.
  const stockByVid = await cjApi.getProductStock(pid);
  const stockFor = (vid) =>
    stockByVid ? (stockByVid[vid] || 0) : config.assumedStock;

  const variants = (detail.variants || []).map((v) => ({
    // Kept in the casing ProductVariationModel.toJson used, inside jsonb.
    Id: String(v.vid || ""),
    SKU: v.sku || "",
    Image: v.image || detail.image || "",
    Price: Number(v.retailPriceUsd) || 0,
    SalePrice: Number(v.retailPriceUsd) || 0,
    Stock: stockFor(v.vid),
    AttributeValues: v.attributes || {},
  }));

  return {
    description: detail.description || "",
    imageUrls: Array.isArray(detail.images) && detail.images.length > 0 ?
      detail.images : [detail.image].filter(Boolean),
    variants,
    productAttributes: buildAttributes(variants),
    stockAvailable: variants.reduce((sum, v) => sum + v.Stock, 0) ||
        config.assumedStock,
    videos: detail.videos || [],
    detailSyncedAt: new Date().toISOString(),
  };
}

/**
 * Derives the product-level attribute list the variant picker renders from
 * the variants themselves, preserving first-seen order for both names and
 * values so the picker's rows are stable between syncs.
 * @param {Array<object>} variants Mapped variant documents.
 * @return {Array<{Name: string, Values: Array<string>}>} Picker rows.
 */
function buildAttributes(variants) {
  const byName = new Map();
  for (const variant of variants) {
    for (const [name, value] of Object.entries(variant.AttributeValues || {})) {
      if (!value) continue;
      if (!byName.has(name)) byName.set(name, new Set());
      byName.get(name).add(value);
    }
  }
  // `Values` is always an array: ProductAttributeModel.fromJson used to throw
  // on a missing key, and the picker filters on it either way.
  return [...byName.entries()].map(([Name, values]) => ({
    Name,
    Values: [...values],
  }));
}

/**
 * Looks up which of `ids` already exist, so `createdAt` is only stamped on
 * genuinely new products - the home feed orders by it.
 * @param {Array<string>} ids Product ids.
 * @return {Promise<Set<string>>} The subset that already exists.
 */
async function existingProductIds(ids) {
  const found = new Set();
  for (let i = 0; i < ids.length; i += 100) {
    const rows = must(await db().from(PRODUCTS)
        .select("id").in("id", ids.slice(i, i + 100)));
    for (const row of rows) found.add(row.id);
  }
  return found;
}

/**
 * Writes every product matched by the configured sources.
 * @param {object} config Catalog config.
 * @param {string} runId Identifier for this run, used to spot stale products.
 * @return {Promise<object>} Counts for logging.
 */
async function syncProducts(config, runId) {
  const bySource = new Map();
  let budget = config.maxProductsPerRun;

  for (const source of config.sources) {
    if (budget <= 0) break;
    if (!source?.categoryId && !source?.keyword) continue;
    try {
      const products = await collectFromSource(source, budget);
      for (const product of products) {
        const id = String(product.id || "");
        if (!id || config.blockedProductIds.has(id)) continue;
        if (!bySource.has(id)) {
          bySource.set(id, { product, featured: source.featured === true });
          budget--;
        }
      }
    } catch (err) {
      // One bad source (a deleted CJ category, say) must not abort the run.
      console.error(
          `catalogSync: source ${JSON.stringify(source)} failed:`, err.message);
    }
    await pace();
  }

  const ids = [...bySource.keys()];
  if (ids.length === 0) return { written: 0, created: 0 };

  const existing = await existingProductIds(ids);
  const featuredOrder = new Map(
      config.featuredProductIds.map((id, index) => [String(id), index]));

  let written = 0;
  let created = 0;
  const now = new Date().toISOString();
  // New and existing rows go in separate upserts: PostgREST sends one
  // column list per request, and only a new row may carry createdAt - on
  // an existing one it would reset the home feed's ordering.
  const fresh = [];
  const known = [];
  for (const id of ids) {
    const { product, featured } = bySource.get(id);
    const pinnedRank = featuredOrder.get(id);
    const row = {
      id,
      ...mapSummary(product, config),
      isFeatured: pinnedRank !== undefined || featured,
      // Pinned products lead the feed in the order they were configured;
      // anything else featured falls in behind them.
      featuredRank: pinnedRank !== undefined ? pinnedRank : 1000,
      lastSyncedAt: now,
      syncRunId: runId,
      updatedAt: now,
    };
    if (existing.has(id)) {
      known.push(toRow(row));
    } else {
      // detail_synced_at is left at its null default, which is how
      // `enrichProducts` finds new products to fill in.
      fresh.push(toRow({ ...row, createdAt: now }));
      created++;
    }
  }
  for (const rows of [fresh, known]) {
    for (let i = 0; i < rows.length; i += BATCH_LIMIT) {
      const batch = rows.slice(i, i + BATCH_LIMIT);
      must(await db().from(PRODUCTS).upsert(batch));
      written += batch.length;
    }
  }
  return { written, created };
}

/**
 * Fills in detail for products that don't have it yet, oldest-first, within
 * this run's CJ call budget.
 * @param {object} config Catalog config.
 * @return {Promise<object>} Counts for logging.
 */
async function enrichProducts(config) {
  const pending = must(await db().from(PRODUCTS)
      .select("id")
      .eq("source", "cj")
      .is("detail_synced_at", null)
      .order("created_at", { ascending: true })
      .limit(config.maxDetailCallsPerRun));

  let enriched = 0;
  for (const { id } of pending) {
    const fields = await fetchDetailFields(id, config);
    if (fields) {
      must(await db().from(PRODUCTS).update(toRow(fields)).eq("id", id));
      enriched++;
    } else {
      // Don't retry a permanently broken product every single run.
      must(await db().from(PRODUCTS).update({
        detail_synced_at: new Date().toISOString(),
        detail_sync_error: true,
      }).eq("id", id));
    }
    await pace();
  }
  return { enriched, pending: pending.length };
}

/**
 * Deactivates products the configured sources no longer return. They are
 * never deleted - existing orders and reviews reference them, and the client
 * filters on `isActive` anyway.
 * @param {string} runId The current run's id.
 * @return {Promise<object>} Counts for logging.
 */
async function deactivateStale(runId) {
  const stale = must(await db().from(PRODUCTS)
      .update({
        is_active: false,
        is_featured: false,
        updated_at: new Date().toISOString(),
      })
      .eq("source", "cj")
      .eq("is_active", true)
      .or(`sync_run_id.is.null,sync_run_id.neq.${runId}`)
      .select("id"));
  return { deactivated: stale.length };
}

/**
 * One full catalog pass: categories, then products, then a bounded detail
 * enrichment, then retire anything the sources dropped.
 * @return {Promise<object>} A summary suitable for logging.
 */
async function runCatalogSync() {
  const config = await getCatalogConfig();
  if (config.sources.length === 0) {
    console.warn(
        "catalogSync: app_config 'catalog' has no sources - nothing to sync. " +
        "Set its value to { sources: [{ categoryId | keyword, limit }] }.");
    return { skipped: true };
  }
  const runId = `${Date.now()}`;
  const summary = { runId };

  if (config.syncCategories) {
    summary.categories = await syncCategories();
  }
  summary.products = await syncProducts(config, runId);
  summary.detail = await enrichProducts(config);
  summary.stale = await deactivateStale(runId);
  return summary;
}

export {
  runCatalogSync,
  syncCategories,
  syncProducts,
  enrichProducts,
  deactivateStale,
  getCatalogConfig,
  flattenCategories,
  normalizeCategoryNode,
  mapSummary,
  buildAttributes,
};
