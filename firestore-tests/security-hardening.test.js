// Proves the 2026-09-11 security fixes to the flat (non-tenant-scoped)
// collections hold: a user cannot grant themselves admin, a seller cannot
// edit another seller's listing, and no client can write an order document
// directly (order creation is Cloud-Function-only — see
// functions/src/orders.ts). See WORKLOG.md, 2026-09-11 entry.
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

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    // A distinct project id from tenant-isolation.test.js — node --test
    // runs test files concurrently against the same running emulator, and
    // sharing a project id let one file's clearFirestore() race and wipe
    // the other file's fixtures mid-test.
    projectId: 'sellora-rules-test-security',
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
  });
});

test('users: a signed-in user cannot grant themselves admin', async () => {
  const asBuyerX = testEnv.authenticatedContext(BUYER_X).firestore();
  await assertFails(
    asBuyerX.doc(`users/${BUYER_X}`).update({ role: 'admin' }),
  );
  // Non-role fields on their own doc are still editable.
  await assertSucceeds(
    asBuyerX.doc(`users/${BUYER_X}`).update({ name: 'Jane B.' }),
  );
});

test('users: an admin can change another user\'s role', async () => {
  const asAdmin = testEnv.authenticatedContext(ADMIN, { admin: true }).firestore();
  await assertSucceeds(
    asAdmin.doc(`users/${BUYER_X}`).update({ role: 'seller' }),
  );
});

test('users: a signed-in user can no longer read every user document', async () => {
  const asBuyerX = testEnv.authenticatedContext(BUYER_X).firestore();
  await assertFails(asBuyerX.doc(`users/${SELLER_A}`).get());
  await assertSucceeds(asBuyerX.doc(`users/${BUYER_X}`).get());

  const asAdmin = testEnv.authenticatedContext(ADMIN, { admin: true }).firestore();
  await assertSucceeds(asAdmin.doc(`users/${SELLER_A}`).get());
});

test('listings: a seller cannot edit another seller\'s listing', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context
      .firestore()
      .doc('listings/l1')
      .set({ sellerId: SELLER_A, title: "A's listing" });
  });

  const asSellerB = testEnv.authenticatedContext(SELLER_B).firestore();
  await assertFails(
    asSellerB.doc('listings/l1').update({ title: 'Hijacked' }),
  );

  const asSellerA = testEnv.authenticatedContext(SELLER_A).firestore();
  await assertSucceeds(
    asSellerA.doc('listings/l1').update({ title: 'Updated by owner' }),
  );
});

test('listings: a seller cannot create a listing under someone else\'s sellerId', async () => {
  const asSellerB = testEnv.authenticatedContext(SELLER_B).firestore();
  await assertFails(
    asSellerB.doc('listings/l2').set({ sellerId: SELLER_A, title: 'Planted' }),
  );
  await assertSucceeds(
    asSellerB.doc('listings/l3').set({ sellerId: SELLER_B, title: 'Own listing' }),
  );
});

test('orders: no client can create an order document directly', async () => {
  const asBuyerX = testEnv.authenticatedContext(BUYER_X).firestore();
  await assertFails(
    asBuyerX.doc('orders/o1').set({ buyerId: BUYER_X, total: 1 }),
  );

  const asAdmin = testEnv.authenticatedContext(ADMIN, { admin: true }).firestore();
  await assertFails(
    asAdmin.doc('orders/o1').set({ buyerId: BUYER_X, total: 1 }),
  );
});
