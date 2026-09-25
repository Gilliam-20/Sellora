const { db, admin } = require("./firebaseAdmin");
const { badRequest, notFound } = require("./errors");

const RATING_KEYS = ["1", "2", "3", "4", "5"];

/** @return {object} A fresh 1-5 star tally, all zero. */
function emptyBreakdown() {
  return { "1": 0, "2": 0, "3": 0, "4": 0, "5": 0 };
}

/**
 * @param {object} breakdown Star tally, e.g. { "1": 0, ..., "5": 3 }.
 * @return {{ratingCount: number, ratingAvg: number}} The derived aggregate.
 */
function summarize(breakdown) {
  const ratingCount = RATING_KEYS.reduce(
      (sum, key) => sum + (breakdown[key] || 0), 0,
  );
  const ratingSum = RATING_KEYS.reduce(
      (sum, key) => sum + Number(key) * (breakdown[key] || 0), 0,
  );
  const ratingAvg = ratingCount > 0 ?
    Math.round((ratingSum / ratingCount) * 100) / 100 : 0;
  return { ratingCount, ratingAvg };
}

/**
 * A review only counts as a verified purchase if the reviewer has a paid
 * order that actually contains this product.
 * @param {string} uid Reviewer's Firebase Auth uid.
 * @param {string} productId Product being reviewed.
 * @return {Promise<boolean>} Whether the reviewer has bought this product.
 */
async function hasVerifiedPurchase(uid, productId) {
  const snap = await db.collection("orders")
      .where("userId", "==", uid)
      .where("status", "==", "paid")
      .get();
  return snap.docs.some((doc) =>
    (doc.data().fulfillmentItems || [])
        .some((item) => item.pid === productId),
  );
}

/**
 * @param {object} decoded Decoded Firebase Auth ID token of the reviewer.
 * @return {Promise<{displayName: string, photoUrl: (string|null)}>}
 */
async function getReviewerProfile(decoded) {
  const userSnap = await db.collection("users").doc(decoded.uid).get();
  const user = userSnap.exists ? userSnap.data() : {};
  const displayName = user.displayName ||
      [user.firstName, user.lastName].filter(Boolean).join(" ").trim() ||
      decoded.name || decoded.email || "Anonymous";
  return { displayName, photoUrl: user.photoUrl || decoded.picture || null };
}

/**
 * Creates or updates the caller's review for a product, keeping the
 * product's ratingAvg/ratingCount/ratingBreakdown aggregate in sync inside
 * the same transaction so it can never drift from the underlying reviews.
 * One review per user per product - the review doc id is the reviewer's uid.
 * @param {object} args
 * @param {string} args.uid Reviewer's Firebase Auth uid.
 * @param {object} args.decoded Decoded Firebase Auth ID token.
 * @param {string} args.productId Product being reviewed.
 * @param {number} args.rating Star rating, 1-5.
 * @param {string} args.comment Review text.
 * @return {Promise<{verifiedPurchase: boolean}>}
 */
async function submitReview({ uid, decoded, productId, rating, comment }) {
  if (!productId || typeof productId !== "string") {
    throw badRequest("productId is required");
  }
  if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
    throw badRequest("rating must be an integer between 1 and 5");
  }
  const trimmedComment = (comment || "").toString().trim();
  if (!trimmedComment) {
    throw badRequest("comment is required");
  }
  if (trimmedComment.length > 1000) {
    throw badRequest("comment must be 1000 characters or fewer");
  }

  const productRef = db.collection("products").doc(productId);
  const reviewRef = productRef.collection("reviews").doc(uid);
  const [verifiedPurchase, profile] = await Promise.all([
    hasVerifiedPurchase(uid, productId),
    getReviewerProfile(decoded),
  ]);

  await db.runTransaction(async (tx) => {
    const [productSnap, reviewSnap] = await Promise.all([
      tx.get(productRef),
      tx.get(reviewRef),
    ]);
    if (!productSnap.exists) throw notFound("Product not found");

    const breakdown = {
      ...emptyBreakdown(),
      ...(productSnap.data().ratingBreakdown || {}),
    };
    const previousRating = reviewSnap.exists ?
      reviewSnap.data().rating : null;
    if (previousRating != null) {
      const key = String(previousRating);
      breakdown[key] = Math.max(0, (breakdown[key] || 0) - 1);
    }
    breakdown[String(rating)] = (breakdown[String(rating)] || 0) + 1;
    const { ratingCount, ratingAvg } = summarize(breakdown);

    tx.set(reviewRef, {
      uid,
      displayName: profile.displayName,
      photoUrl: profile.photoUrl,
      rating,
      comment: trimmedComment,
      verifiedPurchase,
      createdAt: reviewSnap.exists ?
        reviewSnap.data().createdAt :
        admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.update(productRef, {
      ratingAvg, ratingCount, ratingBreakdown: breakdown,
    });
  });

  return { verifiedPurchase };
}

/**
 * Removes the caller's own review and re-syncs the product's aggregate.
 * @param {object} args
 * @param {string} args.uid Reviewer's Firebase Auth uid.
 * @param {string} args.productId Product the review belongs to.
 * @return {Promise<void>}
 */
async function deleteReview({ uid, productId }) {
  if (!productId || typeof productId !== "string") {
    throw badRequest("productId is required");
  }
  const productRef = db.collection("products").doc(productId);
  const reviewRef = productRef.collection("reviews").doc(uid);

  await db.runTransaction(async (tx) => {
    const [productSnap, reviewSnap] = await Promise.all([
      tx.get(productRef),
      tx.get(reviewRef),
    ]);
    if (!reviewSnap.exists) throw notFound("Review not found");
    if (!productSnap.exists) throw notFound("Product not found");

    const breakdown = {
      ...emptyBreakdown(),
      ...(productSnap.data().ratingBreakdown || {}),
    };
    const rating = reviewSnap.data().rating;
    const key = String(rating);
    breakdown[key] = Math.max(0, (breakdown[key] || 0) - 1);
    const { ratingCount, ratingAvg } = summarize(breakdown);

    tx.delete(reviewRef);
    tx.update(productRef, {
      ratingAvg, ratingCount, ratingBreakdown: breakdown,
    });
  });
}

module.exports = { submitReview, deleteReview };
