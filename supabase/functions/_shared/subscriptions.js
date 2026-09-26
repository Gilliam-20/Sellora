// Seller subscription billing. Mirrors orders.js's split of responsibility:
// this module owns the billing tables (billing_history/subscriptions, and
// the profile fields they mirror onto), while api/index.ts orchestrates the
// actual payment-provider calls.
import { db, must } from "./db.js";
import { badRequest, notFound } from "./errors.js";
import { fromRow } from "./rows.js";

/**
 * Creates a pending billing_history ledger entry for a seller's subscription
 * purchase. The plan's price/terms are snapshotted onto the entry now, so a
 * later admin price edit never rewrites what this entry actually charged -
 * the same "never modify historical fees" precedent orders.js's own fee
 * fields already follow.
 * @param {{sellerId: string, planId: string}} args
 * @return {Promise<object>} The created entry, in the camelCase shape
 *   `BillingEntry.fromMap` reads.
 */
async function createBillingEntry({ sellerId, planId }) {
  if (!planId || typeof planId !== "string") {
    throw badRequest("planId is required");
  }
  const plan = must(await db().from("subscription_plans")
      .select("id, name, price_kes, price_usd, billing_period_days")
      .eq("id", planId).maybeSingle());
  if (!plan) {
    throw notFound(`Plan ${planId} not found`);
  }

  const row = must(await db().from("billing_history").insert({
    seller_id: sellerId,
    plan_id: planId,
    plan_name: plan.name || planId,
    amount_kes: Number(plan.price_kes || 0),
    amount_usd: Number(plan.price_usd || 0),
    billing_period_days: Number(plan.billing_period_days || 30),
    status: "pending",
    payment_provider: "INTASEND",
  }).select().single());
  return entryFromRow(row);
}

/**
 * @param {object} row A billing_history row.
 * @return {object} camelCase entry. Postgres numerics arrive as numbers or
 *   strings depending on size, so the amounts are coerced here once.
 */
function entryFromRow(row) {
  const entry = fromRow(row);
  entry.amountKes = Number(entry.amountKes);
  entry.amountUsd = Number(entry.amountUsd);
  return entry;
}

/**
 * @param {string} entryId
 * @return {Promise<object|null>} The entry, or null if it doesn't exist -
 *   used by intasendWebhook to tell "not a billing entry" apart from a
 *   genuine error, without throwing for the common case of an api_ref that
 *   simply belongs to an order instead.
 */
async function getBillingEntry(entryId) {
  const row = must(await db().from("billing_history")
      .select("*").eq("id", entryId).maybeSingle());
  return row ? entryFromRow(row) : null;
}

/**
 * Records which payment attempt a billing entry started, so a later webhook
 * can check the invoice it's confirming was actually the one this entry
 * asked for - mirrors orders.js's attachPaymentAttempt/paymentRefMatches
 * pair, kept to a single latest attempt (not a full history) since a
 * subscription purchase isn't expected to see the same method-switching
 * retries a cart checkout can.
 * @param {string} entryId
 * @param {{paymentMethod: string, paymentProvider: string, paymentRef: object}} args
 */
async function attachBillingPaymentAttempt(entryId, { paymentMethod, paymentProvider, paymentRef }) {
  must(await db().from("billing_history").update({
    payment_method: paymentMethod,
    payment_provider: paymentProvider,
    payment_ref: paymentRef,
  }).eq("id", entryId).eq("status", "pending"));
}

/**
 * Whether `ref` identifies the payment attempt this billing entry actually
 * started. Without this check, re-verifying an invoice with IntaSend alone
 * isn't enough - a genuinely-completed invoice for a *different* payment
 * could otherwise be paired with someone else's billing entry id and
 * activate their subscription for free. Same reasoning as orders.js's
 * paymentRefMatches.
 * @param {object|null} entry
 * @param {{invoiceId: (string|undefined), checkoutId: (string|undefined)}} ref
 * @return {boolean}
 */
function billingRefMatches(entry, { invoiceId, checkoutId }) {
  if (!entry || !entry.paymentRef) return false;
  if (!invoiceId && !checkoutId) return false;
  return Boolean(
      (invoiceId && entry.paymentRef.invoiceId === invoiceId) ||
      (checkoutId && entry.paymentRef.checkoutId === checkoutId),
  );
}

/**
 * Pure decision: given a billing_history entry's current status, should a
 * payment confirmation actually apply? IntaSend may retry the webhook after
 * a transient failure, and a confirmation for an already-paid entry must be
 * a no-op, not a second activation with a fresh period.
 * @param {object|null} entry
 * @return {boolean}
 */
function isPayable(entry) {
  return Boolean(entry) && entry.status === "pending";
}

/**
 * Marks a pending billing_history entry paid and activates the seller's
 * subscription: upserts `subscriptions` and mirrors plan/period/status onto
 * the seller's profile, which no client may write. All of it happens in the
 * `activate_subscription` SQL function, in one transaction, and only while
 * the entry is still pending - so a webhook and a poll racing on the same
 * entry activate it once.
 * @param {string} entryId
 * @param {{paymentReference: (string|undefined)}=} opts
 * @return {Promise<object>} `{ alreadyHandled, sellerId, planId, currentPeriodEnd? }`.
 */
async function activatePendingSubscription(entryId, { paymentReference } = {}) {
  return must(await db().rpc("activate_subscription", {
    p_entry_id: entryId,
    p_payment_reference: paymentReference || null,
  }));
}

export {
  createBillingEntry,
  getBillingEntry,
  attachBillingPaymentAttempt,
  billingRefMatches,
  isPayable,
  activatePendingSubscription,
};
