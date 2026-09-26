/**
 * Product synchronization: keeps sellers' listings in step with CJ.
 *
 * A listing snapshots CJ's cost at import time. When CJ's cost rises past
 * what the seller's price covers, createOrder refuses the sale (lineRefusal's
 * price floor), and when CJ stops offering a product, getVariant fails at
 * checkout - either way buyers can't buy it, and until now nothing told the
 * seller why. This job re-reads CJ for a batch of listed products (oldest
 * check first), refreshes each listing's cost, and flags and notifies the
 * seller when the listing can't be sold.
 *
 * It only informs. Unlisting stays the seller's call - and CJ's response
 * shapes aren't yet confirmed against a real account, so a misread response
 * must not be able to empty anyone's store.
 */
import { db, must } from "./db.js";
import * as cjApiModule from "./cjApi.js";
import { lineRefusal } from "./orders.js";
import { logWarning } from "./logging.js";

// Distinct CJ products per run. One CJ call each, paced like catalogSync,
// so a run stays well inside an Edge Function's wall-clock limit.
const BATCH = 40;
const CJ_CALL_SPACING_MS = 400;

const round2 = (n) => Math.round(n * 100) / 100;

/**
 * What CJ's current prices mean for one listing.
 * @param {{sell_price: (number|string), variants: Array}} listing A
 *   `products` row (enabled variants carry `vid`; `enabled: false` is off).
 * @param {Array<{vid: string, supplierPriceUsd: (number|null)}>} cjVariants
 *   CJ's variants for the product, as cjApi.getVariantPrices returns them.
 * @return {{costPrice: (number|null), variants: Array,
 *   alert: (string|null)}} The listing's new cost (its dearest sellable
 *   variant, which is what the import screen prices against), its variants
 *   with refreshed `costPrice`, and `below_cost`, `unavailable` or null.
 */
function assessListing(listing, cjVariants) {
  const prices = new Map();
  for (const v of cjVariants || []) {
    const price = Number(v?.supplierPriceUsd);
    if (v?.vid && Number.isFinite(price) && price > 0) prices.set(v.vid, price);
  }
  const own = Array.isArray(listing.variants) ? listing.variants : [];
  const variants = own.map((v) =>
    v && prices.has(v.vid) ? { ...v, costPrice: prices.get(v.vid) } : v);

  // A listing without its own variant list sells any of CJ's.
  const sellable = own.length ?
    own.filter((v) => v && v.enabled !== false && prices.has(v.vid))
        .map((v) => prices.get(v.vid)) :
    [...prices.values()];
  if (sellable.length === 0) {
    return { costPrice: null, variants, alert: "unavailable" };
  }
  const costPrice = round2(Math.max(...sellable));
  const refusal = lineRefusal({
    supplierUnitPriceUsd: costPrice,
    retailUnitPriceUsd: Number(listing.sell_price),
    quantity: 1,
  });
  return { costPrice, variants, alert: refusal ? "below_cost" : null };
}

/**
 * The seller's notification for a newly raised alert.
 * @param {string} alert `below_cost` or `unavailable`.
 * @param {{title: string, sell_price: *}} listing
 * @param {number|null} costPrice
 * @return {{title: string, message: string}}
 */
function alertNotice(alert, listing, costPrice) {
  const name = String(listing.title || "A listed product").slice(0, 120);
  if (alert === "unavailable") {
    return {
      title: `No longer available from CJ: ${name}`,
      message: `CJ Dropshipping isn't offering "${name}" any more, so buyers ` +
        "can't check it out. Unlist it, or import a replacement.",
    };
  }
  return {
    title: `Price below cost: ${name}`,
    message: `CJ's cost for "${name}" is now $${costPrice.toFixed(2)}. ` +
      `At your price of $${Number(listing.sell_price).toFixed(2)}, it doesn't ` +
      "cover that cost plus Sellora's 7% fee, so checkout refuses it. " +
      "Raise the price or unlist it.",
  };
}

/** @return {Promise<void>} Resolves after the CJ pacing interval. */
function pace() {
  return new Promise((resolve) => setTimeout(resolve, CJ_CALL_SPACING_MS));
}

/**
 * One run: up to `batch` distinct CJ products, never-checked first.
 * @param {object=} deps Injectable for tests.
 * @return {Promise<object>} Counts for the job log.
 */
async function syncListings({ cjApi = cjApiModule, wait = pace, batch = BATCH } = {}) {
  // Several stores can list the same CJ product, so over-fetch and dedupe.
  const queue = must(await db().from("products")
      .select("id")
      .eq("is_listed", true)
      .order("supplier_checked_at", { ascending: true, nullsFirst: true })
      .limit(batch * 5));
  const pids = [...new Set((queue || []).map((r) => r.id))].slice(0, batch);

  const summary = { products: pids.length, listings: 0, alerts: 0, cleared: 0, failed: 0 };
  for (const [i, pid] of pids.entries()) {
    if (i > 0) await wait();
    const checkedAt = new Date().toISOString();
    let cjVariants;
    try {
      cjVariants = await cjApi.getVariantPrices(pid);
    } catch (err) {
      // An outage or an unexpected shape: leave every alert as it was, but
      // move the product to the back of the queue so it can't block others.
      summary.failed++;
      logWarning("listing_sync_cj_failed", { pid }, err);
      must(await db().from("products")
          .update({ supplier_checked_at: checkedAt })
          .eq("id", pid).eq("is_listed", true));
      continue;
    }

    const listings = must(await db().from("products")
        .select("store_id, id, seller_id, title, sell_price, variants, supplier_alert")
        .eq("id", pid).eq("is_listed", true)) || [];
    for (const listing of listings) {
      summary.listings++;
      const { costPrice, variants, alert } = assessListing(listing, cjVariants);
      const update = { variants, supplier_alert: alert, supplier_checked_at: checkedAt };
      if (costPrice !== null) update.cost_price = costPrice;
      must(await db().from("products").update(update)
          .eq("store_id", listing.store_id).eq("id", listing.id));

      if (alert && alert !== listing.supplier_alert) {
        summary.alerts++;
        must(await db().from("notifications").insert({
          recipient_id: listing.seller_id,
          ...alertNotice(alert, listing, costPrice),
        }));
      } else if (!alert && listing.supplier_alert) {
        summary.cleared++;
      }
    }
  }
  return summary;
}

export { assessListing, alertNotice, syncListings, BATCH };
