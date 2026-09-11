// Proves the tenant-isolation property Phase 2 (see WORKLOG.md, 2026-09-11
// entry) requires: one seller can never read or write another seller's
// store-scoped products, orders, or customers, even though the top-level
// `stores/{storeId}` document itself is publicly readable.
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

const STORE_A = 'store-a';
const STORE_B = 'store-b';
const SELLER_A = 'seller-a';
const SELLER_B = 'seller-b';
const BUYER_X = 'buyer-x';
const BUYER_Y = 'buyer-y';

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'sellora-rules-test',
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
  // Seed the fixtures every test needs, bypassing rules the way a Cloud
  // Function (admin SDK) would.
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.doc(`users/${SELLER_A}`).set({ role: 'seller' });
    await db.doc(`users/${SELLER_B}`).set({ role: 'seller' });
    await db.doc(`users/${BUYER_X}`).set({ role: 'buyer' });
    await db.doc(`users/${BUYER_Y}`).set({ role: 'buyer' });
    await db.doc(`stores/${STORE_A}`).set({ sellerId: SELLER_A, slug: 'store-a' });
    await db.doc(`stores/${STORE_B}`).set({ sellerId: SELLER_B, slug: 'store-b' });
  });
});

test('products: only the owning seller can write into their store', async () => {
  const asSellerA = testEnv.authenticatedContext(SELLER_A).firestore();
  const asSellerB = testEnv.authenticatedContext(SELLER_B).firestore();

  await assertSucceeds(
    asSellerA.doc(`stores/${STORE_A}/products/p1`).set({ title: 'Owned by A' }),
  );
  await assertFails(
    asSellerB.doc(`stores/${STORE_A}/products/p2`).set({ title: 'Planted by B' }),
  );
});

test('products: the storefront stays publicly readable for guests', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context
      .firestore()
      .doc(`stores/${STORE_A}/products/p1`)
      .set({ title: 'Owned by A' });
  });

  const guest = testEnv.unauthenticatedContext().firestore();
  await assertSucceeds(guest.doc(`stores/${STORE_A}/products/p1`).get());
});

test('orders: a store owner cannot read another store\'s orders', async () => {
  const asBuyerX = testEnv.authenticatedContext(BUYER_X).firestore();
  await assertSucceeds(
    asBuyerX.doc(`stores/${STORE_A}/orders/o1`).set({ buyerId: BUYER_X, total: 1000 }),
  );

  const asSellerA = testEnv.authenticatedContext(SELLER_A).firestore();
  const asSellerB = testEnv.authenticatedContext(SELLER_B).firestore();
  const asBuyerY = testEnv.authenticatedContext(BUYER_Y).firestore();

  await assertSucceeds(asSellerA.doc(`stores/${STORE_A}/orders/o1`).get());
  await assertFails(asSellerB.doc(`stores/${STORE_A}/orders/o1`).get());
  await assertFails(asBuyerY.doc(`stores/${STORE_A}/orders/o1`).get());
});

test('orders: only the owning seller (or admin) can update fulfillment status', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context
      .firestore()
      .doc(`stores/${STORE_A}/orders/o1`)
      .set({ buyerId: BUYER_X, status: 'pending' });
  });

  const asSellerB = testEnv.authenticatedContext(SELLER_B).firestore();
  const asSellerA = testEnv.authenticatedContext(SELLER_A).firestore();

  await assertFails(
    asSellerB.doc(`stores/${STORE_A}/orders/o1`).update({ status: 'shipped' }),
  );
  await assertSucceeds(
    asSellerA.doc(`stores/${STORE_A}/orders/o1`).update({ status: 'shipped' }),
  );
});

test('customers: a buyer\'s store profile is private to them, their store\'s seller, and admins', async () => {
  const asBuyerX = testEnv.authenticatedContext(BUYER_X).firestore();
  await assertSucceeds(
    asBuyerX
      .doc(`stores/${STORE_A}/customers/${BUYER_X}`)
      .set({ uid: BUYER_X, email: 'x@example.com' }),
  );

  const asBuyerY = testEnv.authenticatedContext(BUYER_Y).firestore();
  const asSellerB = testEnv.authenticatedContext(SELLER_B).firestore();
  const asSellerA = testEnv.authenticatedContext(SELLER_A).firestore();

  await assertFails(asBuyerY.doc(`stores/${STORE_A}/customers/${BUYER_X}`).get());
  await assertFails(asSellerB.doc(`stores/${STORE_A}/customers/${BUYER_X}`).get());
  await assertSucceeds(asSellerA.doc(`stores/${STORE_A}/customers/${BUYER_X}`).get());
  await assertSucceeds(asBuyerX.doc(`stores/${STORE_A}/customers/${BUYER_X}`).get());
});
