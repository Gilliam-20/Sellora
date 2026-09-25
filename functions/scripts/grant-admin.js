#!/usr/bin/env node
/**
 * Provisions (or revokes) Sellora's single admin account.
 *
 *   node scripts/grant-admin.js admin@yourdomain.com [--name "Ops Admin"]
 *   node scripts/grant-admin.js admin@yourdomain.com --revoke
 *
 * The admin is one dedicated email, never a seller's or buyer's account:
 * there is no admin sign-up in the app, and firestore.rules refuses any
 * client write that would create a `role: admin` profile. This script is
 * the only way in. It sets the `admin` custom claim (what firestore.rules'
 * isAdmin() and refundOrder/runCatalogSync check) and writes the matching
 * `users/{uid}` profile (what the app routes on) together, so the two can't
 * drift apart.
 *
 * Needs Admin SDK credentials for the target project, e.g.
 *   gcloud auth application-default login
 * or GOOGLE_APPLICATION_CREDENTIALS pointing at a service-account key.
 * GCLOUD_PROJECT overrides the default project (sellora-20).
 */
"use strict";

const ROLE_ADMIN = "admin";

/**
 * @param {string[]} argv Arguments after the script name.
 * @return {{email: string, name: string, revoke: boolean}} Parsed options.
 */
function parseArgs(argv) {
  const opts = { email: "", name: "Sellora Admin", revoke: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--revoke") {
      opts.revoke = true;
    } else if (arg === "--name") {
      opts.name = String(argv[++i] || "").trim() || opts.name;
    } else if (!arg.startsWith("--") && !opts.email) {
      opts.email = arg.trim().toLowerCase();
    } else {
      throw new Error(`Unrecognised argument: ${arg}`);
    }
  }
  if (!/^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$/.test(opts.email)) {
    throw new Error("Usage: grant-admin.js <email> [--name \"Name\"] [--revoke]");
  }
  return opts;
}

/**
 * Grants admin to [email], creating the Auth account if it doesn't exist.
 * Refuses an email that already belongs to a buyer or seller, and refuses a
 * second admin while another account still holds the role.
 * @param {{auth: object, db: object}} deps Admin SDK auth + Firestore.
 * @param {{email: string, name: string}} opts Target account.
 * @return {Promise<{uid: string, created: boolean, resetLink: ?string}>}
 */
async function grantAdmin({ auth, db }, { email, name }) {
  let user;
  let created = false;
  try {
    user = await auth.getUserByEmail(email);
  } catch (e) {
    if (e.code !== "auth/user-not-found") throw e;
    // No password: the admin sets their own through the reset link below,
    // so no credential ever passes through this terminal.
    user = await auth.createUser({ email, emailVerified: true, displayName: name });
    created = true;
  }

  const profileRef = db.collection("users").doc(user.uid);
  const profile = await profileRef.get();
  if (profile.exists && profile.data().role !== ROLE_ADMIN) {
    throw new Error(
        `${email} is already a ${profile.data().role} account. ` +
      "The admin must use its own, separate email.",
    );
  }

  const others = await db.collection("users").where("role", "==", ROLE_ADMIN).get();
  const other = others.docs.find((d) => d.id !== user.uid);
  if (other) {
    throw new Error(
        `${other.data().email || other.id} is already the admin. ` +
      "Revoke it first with --revoke.",
    );
  }

  await auth.setCustomUserClaims(user.uid, { ...(user.customClaims || {}), admin: true });
  await profileRef.set({
    uid: user.uid,
    name,
    email,
    role: ROLE_ADMIN,
    currencyCode: "USD",
    createdAt: profile.exists ?
      (profile.data().createdAt || new Date().toISOString()) :
      new Date().toISOString(),
  }, { merge: true });

  const resetLink = created ? await auth.generatePasswordResetLink(email) : null;
  return { uid: user.uid, created, resetLink };
}

/**
 * Removes admin from [email]: drops the claim, revokes live sessions, and
 * deletes the admin profile so the app treats the account as unprovisioned.
 * @param {{auth: object, db: object}} deps Admin SDK auth + Firestore.
 * @param {{email: string}} opts Target account.
 * @return {Promise<{uid: string}>}
 */
async function revokeAdmin({ auth, db }, { email }) {
  const user = await auth.getUserByEmail(email);
  const claims = { ...(user.customClaims || {}) };
  delete claims.admin;
  await auth.setCustomUserClaims(user.uid, claims);
  await auth.revokeRefreshTokens(user.uid);
  const profileRef = db.collection("users").doc(user.uid);
  const profile = await profileRef.get();
  if (profile.exists && profile.data().role === ROLE_ADMIN) {
    await profileRef.delete();
  }
  return { uid: user.uid };
}

/** CLI entry point. */
async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const admin = require("firebase-admin");
  admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "sellora-20" });
  const deps = { auth: admin.auth(), db: admin.firestore() };

  if (opts.revoke) {
    const { uid } = await revokeAdmin(deps, opts);
    console.log(`Admin revoked for ${opts.email} (${uid}); sessions signed out.`);
    return;
  }
  const { uid, created, resetLink } = await grantAdmin(deps, opts);
  console.log(`Admin granted to ${opts.email} (${uid}).`);
  if (created) {
    console.log("New account — send this one-time password-setup link to the admin only:");
    console.log(resetLink);
  } else {
    console.log("Existing account — sign out and back in for the claim to take effect.");
  }
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e.message || e);
    process.exit(1);
  });
}

module.exports = { parseArgs, grantAdmin, revokeAdmin };
