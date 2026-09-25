// Proves the 2026-09-12 Phase 3 (billing) security model holds: no client
// can write `subscriptions` or `billing_history` directly (both are
// Cloud-Function-only — see functions/lib/subscriptions.js), a seller
// cannot self-activate their own subscription fields on `users/{uid}` but
// can still edit unrelated fields, and an admin can still set them. See
// WORKLOG.md, 2026-09-12 entry.
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
const ADMIN = 'admin-1';

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    // A distinct project id from the other test files — node --test runs
    // test files concurrently against the same running emulator, and
    // sharing a project id lets one file's clearFirestore() race and wipe
    // another file's fixtures mid-test.
    projectId: 'sellora-rules-test-billing',
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
    await db.doc(`users/${SELLER_A}`).set({
      role: 'seller',
      sellerStatus: 'pendingApproval',
    });
    await db.doc(`users/${SELLER_B}`).set({
      role: 'seller',
      sellerStatus: 'pendingApproval',
    });
    await db.doc(`users/${ADMIN}`).set({ role: 'admin' });
    await db.doc(`subscriptions/${SELLER_A}`).set({
      sellerId: SELLER_A,
      planId: 'growth',
      status: 'active',
      orderLimit: 500,
    });
  });
});

test('subscriptions: no client, including the owning seller, can write their own subscription doc', async () => {
  const asSellerA = testEnv.authenticatedContext(SELLER_A).firestore();
  await assertFails(
    asSellerA.doc(`subscriptions/${SELLER_A}`).set({ status: 'active', orderLimit: -1 }),
  );

  const asAdmin = testEnv.authenticatedContext(ADMIN, { admin: true }).firestore();
  await assertFails(
    asAdmin.doc(`subscriptions/${SELLER_A}`).update({ orderLimit: -1 }),
  );
});

test('subscriptions: the owning seller can read their own subscription doc, another seller cannot', async () => {
  const asSellerA = testEnv.authenticatedContext(SELLER_A).firestore();
  await assertSucceeds(asSellerA.doc(`subscriptions/${SELLER_A}`).get());

  const asSellerB = testEnv.authenticatedContext(SELLER_B).firestore();
  await assertFails(asSellerB.doc(`subscriptions/${SELLER_A}`).get());
});

test('subscriptions: admin can read any subscription doc', async () => {
  const asAdmin = testEnv.authenticatedContext(ADMIN, { admin: true }).firestore();
  await assertSucceeds(asAdmin.doc(`subscriptions/${SELLER_A}`).get());
});

test('users: a seller cannot self-activate their own subscription fields', async () => {
  const asSellerA = testEnv.authenticatedContext(SELLER_A).firestore();
  await assertFails(
    asSellerA.doc(`users/${SELLER_A}`).update({
      sellerStatus: 'active',
      subscriptionPlanId: 'growth',
      subscriptionActiveUntil: new Date().toISOString(),
    }),
  );
});

test('users: a seller can still edit unrelated fields on their own doc', async () => {
  const asSellerA = testEnv.authenticatedContext(SELLER_A).firestore();
  await assertSucceeds(
    asSellerA.doc(`users/${SELLER_A}`).update({ name: 'New Name' }),
  );
});

test('users: an admin can still set a seller\'s subscription fields', async () => {
  const asAdmin = testEnv.authenticatedContext(ADMIN, { admin: true }).firestore();
  await assertSucceeds(
    asAdmin.doc(`users/${SELLER_A}`).update({
      sellerStatus: 'active',
      subscriptionPlanId: 'growth',
      subscriptionActiveUntil: new Date().toISOString(),
    }),
  );
});

test('billing_history: no client can write a billing_history entry directly', async () => {
  const asSellerA = testEnv.authenticatedContext(SELLER_A).firestore();
  await assertFails(
    asSellerA.doc('billing_history/bh1').set({ sellerId: SELLER_A, status: 'paid' }),
  );

  const asAdmin = testEnv.authenticatedContext(ADMIN, { admin: true }).firestore();
  await assertFails(
    asAdmin.doc('billing_history/bh1').set({ sellerId: SELLER_A, status: 'paid' }),
  );
});
