// Seller subscription billing. Mirrors orders.js's split of responsibility:
// this module owns Firestore state (billing_history/subscriptions/users),
// while index.js orchestrates the actual payment-provider calls.
const { db } = require("./firebaseAdmin");

const BILLING_HISTORY = db.collection("billing_history");
const SUBSCRIPTIONS = db.collection("subscriptions");
const PLANS = db.collection("subscription_plans");
const USERS = db.collection("users");

/**
 * Creates a pending billing_history ledger entry for a seller's subscription
 * purchase. The plan's price/terms are snapshotted onto the entry now, so a
 * later admin price edit never rewrites what this entry actually charged -
 * the same "never modify historical fees" precedent orders.js's own fee
 * fields already follow.
 * @param {{sellerId: string, planId: string}} args
 * @return {Promise<object>} The created entry.
 */
async function createBillingEntry({ sellerId, planId }) {
  if (!planId || typeof planId !== "string") {
    throw new Error("planId is required");
  }
  const planSnap = await PLANS.doc(planId).get();
  if (!planSnap.exists) {
    throw new Error(`Plan ${planId} not found`);
  }
  const plan = planSnap.data();

  const entryRef = BILLING_HISTORY.doc();
  const entry = {
    id: entryRef.id,
    sellerId,
    planId,
    planName: plan.name || planId,
    amountKes: Number(plan.priceKes || 0),
    amountUsd: Number(plan.priceUsd || 0),
    billingPeriodDays: Number(plan.billingPeriodDays || 30),
    status: "pending",
    paymentProvider: "INTASEND",
    paymentReference: null,
    createdAt: new Date().toISOString(),
    paidAt: null,
  };
  await entryRef.set(entry);
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
  const snap = await BILLING_HISTORY.doc(entryId).get();
  if (!snap.exists) return null;
  return { id: snap.id, ...snap.data() };
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
  await BILLING_HISTORY.doc(entryId).update({ paymentMethod, paymentProvider, paymentRef });
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
 * payment confirmation actually apply? Mirrors orders.js's own idempotency
 * reasoning - IntaSend may retry the webhook after a transient failure, and
 * a confirmation for an already-paid entry must be a no-op, not a second
 * activation with a fresh period.
 * @param {object|null} entry
 * @return {boolean}
 */
function isPayable(entry) {
  return Boolean(entry) && entry.status === "pending";
}

/**
 * Marks a pending billing_history entry paid and activates the seller's
 * subscription: upserts subscriptions/{sellerId} and mirrors the read-model
 * fields onto users/{sellerId} (subscriptionPlanId/subscriptionActiveUntil/
 * sellerStatus - the only fields firestore.rules lets the client itself
 * write there is nothing, going forward; only this function may). Safe to
 * call more than once for the same entry - see `isPayable`.
 * @param {string} entryId
 * @param {{paymentReference: (string|undefined)}=} opts
 * @return {Promise<object>} `{ alreadyHandled, sellerId, planId, currentPeriodEnd? }`.
 */
async function activatePendingSubscription(entryId, { paymentReference } = {}) {
  const entryRef = BILLING_HISTORY.doc(entryId);
  const entry = await getBillingEntry(entryId);
  if (!entry) throw new Error("Billing entry not found");
  if (!isPayable(entry)) {
    return { alreadyHandled: true, sellerId: entry.sellerId, planId: entry.planId };
  }

  const planSnap = await PLANS.doc(entry.planId).get();
  const orderLimit = planSnap.exists ? Number(planSnap.data().orderLimit ?? -1) : -1;

  const now = new Date();
  const periodEnd = new Date(
      now.getTime() + Number(entry.billingPeriodDays || 30) * 24 * 60 * 60 * 1000,
  );

  const batch = db.batch();
  batch.update(entryRef, {
    status: "paid",
    paymentReference: paymentReference || null,
    paidAt: now.toISOString(),
  });
  batch.set(SUBSCRIPTIONS.doc(entry.sellerId), {
    sellerId: entry.sellerId,
    planId: entry.planId,
    status: "active",
    orderLimit,
    currentPeriodStart: now.toISOString(),
    currentPeriodEnd: periodEnd.toISOString(),
    lastBillingHistoryId: entryId,
    updatedAt: now.toISOString(),
  }, { merge: true });
  batch.update(USERS.doc(entry.sellerId), {
    subscriptionPlanId: entry.planId,
    subscriptionActiveUntil: periodEnd.toISOString(),
    sellerStatus: "active",
  });
  await batch.commit();

  return {
    alreadyHandled: false,
    sellerId: entry.sellerId,
    planId: entry.planId,
    currentPeriodEnd: periodEnd.toISOString(),
  };
}

module.exports = {
  createBillingEntry,
  getBillingEntry,
  attachBillingPaymentAttempt,
  billingRefMatches,
  isPayable,
  activatePendingSubscription,
};
