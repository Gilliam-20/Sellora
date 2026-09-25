// Proves the PHASE 12 (security + production) rule fixes hold. Each test
// names the hole it closes; see WORKLOG.md's 2026-09-25 PHASE 12 entry.
//
// Run with `npm test` from this directory (spins up the Firestore emulator
// via `firebase emulators:exec`). Requires the Firebase CLI and a JDK.

const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

/** @type {import('@firebase/rules-unit-testing').RulesTestEnvironment} */
let testEnv;

const SELLER_A = 'seller-a';
const SELLER_B = 'seller-b';
const BUYER_X = 'buyer-x';
const ADMIN = 'admin-1';
const CLAIM_ADMIN = 'claim-admin';
const STORE_A = `store-${SELLER_A}`;

const TERMS = {
  sellerTermsAcceptedAt: '2026-09-25T00:00:00.000Z',
  sellerTermsVersion: '2026-09-17',
};

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    // Distinct from the other files' project ids — node --test runs files
    // concurrently against one emulator, and a shared id lets one file's
    // clearFirestore() wipe another's fixtures mid-test.
    projectId: 'sellora-rules-test-production',
    firestore: {
      rules: fs.readFileSync(
        path.resolve(__dirname, '../firestore.rules'),
        'utf8',
      ),
    },
  });
});

test.after(async () => {
  await testEnv.cleanup();
});

test.beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.doc(`users/${SELLER_A}`).set({ role: 'seller' });
    await db.doc(`users/${SELLER_B}`).set({ role: 'seller' });
    await db.doc(`users/${BUYER_X}`).set({ role: 'buyer' });
    await db.doc(`users/${ADMIN}`).set({ role: 'admin' });
    await db.doc(`stores/${STORE_A}`).set({
      id: STORE_A, slug: 'store-a', sellerId: SELLER_A, name: 'A',
    });
    await db.doc('store_slugs/store-a').set({ storeId: STORE_A });
    await db.doc(`stores/${STORE_A}/orders/o1`).set({
      buyerId: BUYER_X, status: 'pending', paymentStatus: 'pending', total: 50,
    });
    await db.doc('orders/o1').set({
      userId: BUYER_X, uid: BUYER_X, sellerId: SELLER_A,
      status: 'pending', paymentStatus: 'pending', cjOrderStatus: 'NOT_PUSHED',
    });
  });
});

// ---- users: self-signup can't mint privilege -------------------------

test('users: a new account cannot create its own doc as admin', async () => {
  const asNew = testEnv.authenticatedContext('new-user').firestore();
  await assertFails(asNew.doc('users/new-user').set({ role: 'admin' }));
});

test('users: a new seller cannot self-create as active or subscribed', async () => {
  const asNew = testEnv.authenticatedContext('new-seller').firestore();
  await assertFails(asNew.doc('users/new-seller').set({
    role: 'seller', sellerStatus: 'active', ...TERMS,
  }));
  await assertFails(asNew.doc('users/new-seller').set({
    role: 'seller', sellerStatus: 'pendingApproval',
    subscriptionPlanId: 'growth', ...TERMS,
  }));
  await assertFails(asNew.doc('users/new-seller').set({
    role: 'seller', sellerStatus: 'pendingApproval',
    subscriptionActiveUntil: '2099-01-01T00:00:00.000Z', ...TERMS,
  }));
});

test('users: the real signup payloads still succeed', async () => {
  // Shapes match UserModel.toMap() from signUpBuyer / signUpSeller,
  // including the explicit nulls.
  const asBuyer = testEnv.authenticatedContext('new-buyer').firestore();
  await assertSucceeds(asBuyer.doc('users/new-buyer').set({
    uid: 'new-buyer', role: 'buyer', sellerStatus: null,
    subscriptionPlanId: null, subscriptionActiveUntil: null,
    sellerTermsAcceptedAt: null, sellerTermsVersion: null,
  }));

  const asSeller = testEnv.authenticatedContext('new-seller').firestore();
  await assertSucceeds(asSeller.doc('users/new-seller').set({
    uid: 'new-seller', role: 'seller', sellerStatus: 'pendingApproval',
    subscriptionPlanId: null, subscriptionActiveUntil: null, ...TERMS,
  }));
});

// ---- admin custom claim ---------------------------------------------

test('admin: the `admin` custom claim is honoured without a role field', async () => {
  const asClaimAdmin = testEnv
    .authenticatedContext(CLAIM_ADMIN, { admin: true })
    .firestore();
  await assertSucceeds(asClaimAdmin.doc(`users/${SELLER_A}`).get());

  const asForged = testEnv
    .authenticatedContext('no-claim', { admin: 'true' })
    .firestore();
  await assertFails(asForged.doc(`users/${SELLER_A}`).get());
});

test('admin: a `role: admin` doc without the claim grants nothing', async () => {
  // ADMIN's users doc carries role: 'admin' (see beforeEach) — the
  // Firestore field alone must no longer pass isAdmin().
  const asRoleOnly = testEnv.authenticatedContext(ADMIN).firestore();
  await assertFails(asRoleOnly.doc(`users/${SELLER_A}`).get());
});

test('admin: even an admin cannot promote another user to admin', async () => {
  const asAdmin = testEnv
    .authenticatedContext(CLAIM_ADMIN, { admin: true })
    .firestore();
  await assertFails(asAdmin.doc(`users/${SELLER_A}`).update({ role: 'admin' }));
  await assertSucceeds(
    asAdmin.doc(`users/${SELLER_A}`).update({ sellerStatus: 'suspended' }),
  );
});

// ---- stores: slugs are unique and immutable ------------------------

test('stores: a store cannot be created without reserving its slug', async () => {
  const asSellerB = testEnv.authenticatedContext(SELLER_B).firestore();
  await assertFails(asSellerB.doc(`stores/store-${SELLER_B}`).set({
    id: `store-${SELLER_B}`, slug: 'store-b', sellerId: SELLER_B,
  }));
});

test('stores: store + slug reservation in one batch succeeds', async () => {
  const asSellerB = testEnv.authenticatedContext(SELLER_B).firestore();
  const batch = asSellerB.batch();
  batch.set(asSellerB.doc(`stores/store-${SELLER_B}`), {
    id: `store-${SELLER_B}`, slug: 'store-b', sellerId: SELLER_B,
  });
  batch.set(asSellerB.doc('store_slugs/store-b'), { storeId: `store-${SELLER_B}` });
  await assertSucceeds(batch.commit());
});

test('stores: a second store cannot claim a slug that is already taken', async () => {
  const asSellerB = testEnv.authenticatedContext(SELLER_B).firestore();
  const batch = asSellerB.batch();
  batch.set(asSellerB.doc(`stores/store-${SELLER_B}`), {
    id: `store-${SELLER_B}`, slug: 'store-a', sellerId: SELLER_B,
  });
  batch.set(asSellerB.doc('store_slugs/store-a'), { storeId: `store-${SELLER_B}` });
  await assertFails(batch.commit());
});

test('stores: malformed slugs and non-seller creators are refused', async () => {
  const asSellerB = testEnv.authenticatedContext(SELLER_B).firestore();
  const bad = asSellerB.batch();
  bad.set(asSellerB.doc(`stores/store-${SELLER_B}`), {
    id: `store-${SELLER_B}`, slug: 'Bad Slug', sellerId: SELLER_B,
  });
  bad.set(asSellerB.doc('store_slugs/Bad Slug'), { storeId: `store-${SELLER_B}` });
  await assertFails(bad.commit());

  const asBuyer = testEnv.authenticatedContext(BUYER_X).firestore();
  const buyerBatch = asBuyer.batch();
  buyerBatch.set(asBuyer.doc(`stores/store-${BUYER_X}`), {
    id: `store-${BUYER_X}`, slug: 'buyer-store', sellerId: BUYER_X,
  });
  buyerBatch.set(asBuyer.doc('store_slugs/buyer-store'), { storeId: `store-${BUYER_X}` });
  await assertFails(buyerBatch.commit());
});

test('stores: the owner can edit branding but not slug or owner', async () => {
  const asSellerA = testEnv.authenticatedContext(SELLER_A).firestore();
  await assertSucceeds(asSellerA.doc(`stores/${STORE_A}`).update({ name: 'A2' }));
  await assertFails(asSellerA.doc(`stores/${STORE_A}`).update({ slug: 'store-b' }));
  await assertFails(asSellerA.doc(`stores/${STORE_A}`).update({ sellerId: SELLER_B }));
});

test('store_slugs: a reservation can never be released or repointed', async () => {
  const asSellerA = testEnv.authenticatedContext(SELLER_A).firestore();
  await assertFails(asSellerA.doc('store_slugs/store-a').delete());
  await assertFails(asSellerA.doc('store_slugs/store-a').set({ storeId: 'other' }));
});

// ---- orders: fulfilment only, never payment ------------------------

test('store orders: no client can create one directly', async () => {
  const asBuyer = testEnv.authenticatedContext(BUYER_X).firestore();
  await assertFails(asBuyer.doc(`stores/${STORE_A}/orders/o2`).set({
    buyerId: BUYER_X, total: 0.01, status: 'pending',
  }));
});

test('orders: a seller can advance status but cannot mark an order paid', async () => {
  const asSellerA = testEnv.authenticatedContext(SELLER_A).firestore();
  for (const p of [`stores/${STORE_A}/orders/o1`, 'orders/o1']) {
    await assertSucceeds(asSellerA.doc(p).update({ status: 'shipped' }));
    await assertFails(asSellerA.doc(p).update({ paymentStatus: 'paid' }));
    await assertFails(asSellerA.doc(p).update({ status: 'shipped', total: 0 }));
    await assertFails(asSellerA.doc(p).update({ status: 'teleported' }));
  }
  await assertFails(asSellerA.doc('orders/o1').update({ cjOrderStatus: 'FAILED' }));
});

test('orders: an admin can correct status but not payment fields', async () => {
  const asAdmin = testEnv.authenticatedContext(ADMIN, { admin: true }).firestore();
  await assertSucceeds(asAdmin.doc('orders/o1').update({ status: 'cancelled' }));
  await assertFails(asAdmin.doc('orders/o1').update({ paymentStatus: 'paid' }));
  await assertFails(asAdmin.doc('orders/o1').update({ refundedAmount: 50 }));
});

test('orders: the buyer can read a createOrder-shaped order (userId, no buyerId)', async () => {
  const asBuyer = testEnv.authenticatedContext(BUYER_X).firestore();
  await assertSucceeds(asBuyer.doc('orders/o1').get());
  const asSellerB = testEnv.authenticatedContext(SELLER_B).firestore();
  await assertFails(asSellerB.doc('orders/o1').get());
});

test('rate_limits: counters are invisible and unwritable to clients', async () => {
  const asBuyer = testEnv.authenticatedContext(BUYER_X).firestore();
  await assertFails(asBuyer.doc(`rate_limits/createOrder_${BUYER_X}`).get());
  await assertFails(asBuyer.doc(`rate_limits/createOrder_${BUYER_X}`).set({ count: 0 }));
});
