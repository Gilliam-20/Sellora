#!/usr/bin/env node
/**
 * Provisions (or revokes) Sellora's single admin account.
 *
 *   node supabase/scripts/grant-admin.js admin@yourdomain.com [--name "Ops Admin"]
 *   node supabase/scripts/grant-admin.js admin@yourdomain.com --revoke
 *
 * The admin is one dedicated email, never a seller's or buyer's account:
 * there is no admin sign-up in the app, and the handle_new_user trigger
 * refuses a self-assigned admin role. This script is the only way in. It
 * sets `app_metadata.role = 'admin'` (what RLS's is_admin() checks, and
 * which only the service role can write) and the matching `role: admin`
 * profile (what the app routes on) together, so the two can't drift apart.
 *
 * Needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (the secret key) in the
 * environment. Run it from a trusted machine only — that key bypasses RLS.
 * No npm dependencies: Node 18+'s fetch talks to the Auth admin API and
 * PostgREST directly.
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
 * @param {{auth: object, db: object}} deps See supabaseDeps() for the shape.
 * @param {{email: string, name: string}} opts Target account.
 * @return {Promise<{uid: string, created: boolean, resetLink: ?string}>}
 */
async function grantAdmin({ auth, db }, { email, name }) {
  const existing = await auth.getUserByEmail(email);
  if (existing) {
    const profile = await db.getProfile(existing.id);
    if (profile && profile.role !== ROLE_ADMIN) {
      throw new Error(
          `${email} is already a ${profile.role} account. ` +
        "The admin must use its own, separate email.",
      );
    }
  }

  const admins = await db.findAdmins();
  const other = admins.find((p) => !existing || p.uid !== existing.id);
  if (other) {
    throw new Error(
        `${other.email || other.uid} is already the admin. ` +
      "Revoke it first with --revoke.",
    );
  }

  let user = existing;
  let created = false;
  if (!user) {
    // Created with the admin role already in app_metadata, so the
    // handle_new_user trigger writes the admin profile in the same
    // transaction. No password: the admin sets their own through the
    // recovery link below, so no credential passes through this terminal.
    user = await auth.createAdminUser({ email, name });
    created = true;
  } else {
    await auth.setAdminRole(user.id, true);
  }

  // Idempotent. It also covers an existing account that has no profile
  // yet, e.g. one created from the Supabase dashboard.
  const profile = await db.getProfile(user.id);
  await db.upsertProfile({
    uid: user.id,
    name,
    email,
    role: ROLE_ADMIN,
    currency_code: "USD",
    ...(profile ? {} : { created_at: new Date().toISOString() }),
  });

  const resetLink = created ? await auth.generateRecoveryLink(email) : null;
  return { uid: user.id, created, resetLink };
}

/**
 * Removes admin from [email]: drops the role, ends every session, and
 * deletes the admin profile so the app treats the account as unprovisioned.
 * @param {{auth: object, db: object}} deps See supabaseDeps() for the shape.
 * @param {{email: string}} opts Target account.
 * @return {Promise<{uid: string}>}
 */
async function revokeAdmin({ auth, db }, { email }) {
  const user = await auth.getUserByEmail(email);
  if (!user) throw new Error(`No account for ${email}.`);
  await auth.setAdminRole(user.id, false);
  await auth.revokeSessions(user.id);
  const profile = await db.getProfile(user.id);
  if (profile && profile.role === ROLE_ADMIN) {
    await db.deleteProfile(user.id);
  }
  return { uid: user.id };
}

/**
 * The real deps, over the Supabase REST APIs with the service-role key.
 * @param {string} url Project URL, e.g. https://abc.supabase.co.
 * @param {string} key Service-role / secret key.
 * @return {{auth: object, db: object}}
 */
function supabaseDeps(url, key) {
  const base = url.replace(/\/+$/, "");
  const call = async (path, { method = "GET", body, prefer } = {}) => {
    const res = await fetch(`${base}${path}`, {
      method,
      headers: {
        "apikey": key,
        "Authorization": `Bearer ${key}`,
        "Content-Type": "application/json",
        ...(prefer ? { Prefer: prefer } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await res.text();
    if (!res.ok) throw new Error(`${method} ${path} failed (${res.status}): ${text}`);
    return text ? JSON.parse(text) : null;
  };
  const eq = (v) => `eq.${encodeURIComponent(v)}`;

  const auth = {
    async getUserByEmail(email) {
      // The admin API has no lookup by email, so page through.
      for (let page = 1; ; page++) {
        const { users } = await call(`/auth/v1/admin/users?page=${page}&per_page=1000`);
        const match = users.find((u) => (u.email || "").toLowerCase() === email);
        if (match) return match;
        if (users.length < 1000) return null;
      }
    },
    createAdminUser({ email, name }) {
      return call("/auth/v1/admin/users", {
        method: "POST",
        body: {
          email,
          email_confirm: true,
          app_metadata: { role: ROLE_ADMIN },
          user_metadata: { name },
        },
      });
    },
    // app_metadata is merged on update, and a null value removes the key.
    setAdminRole(uid, isAdmin) {
      return call(`/auth/v1/admin/users/${uid}`, {
        method: "PUT",
        body: { app_metadata: { role: isAdmin ? ROLE_ADMIN : null } },
      });
    },
    revokeSessions(uid) {
      return call("/rest/v1/rpc/revoke_user_sessions", {
        method: "POST",
        body: { target_uid: uid },
      });
    },
    async generateRecoveryLink(email) {
      const res = await call("/auth/v1/admin/generate_link", {
        method: "POST",
        body: { type: "recovery", email },
      });
      return res.action_link || (res.properties && res.properties.action_link);
    },
  };

  const db = {
    async getProfile(uid) {
      const rows = await call(`/rest/v1/profiles?uid=${eq(uid)}&select=*`);
      return rows[0] || null;
    },
    findAdmins() {
      return call(`/rest/v1/profiles?role=${eq(ROLE_ADMIN)}&select=uid,email`);
    },
    upsertProfile(profile) {
      return call("/rest/v1/profiles?on_conflict=uid", {
        method: "POST",
        body: profile,
        prefer: "resolution=merge-duplicates",
      });
    },
    deleteProfile(uid) {
      return call(`/rest/v1/profiles?uid=${eq(uid)}`, { method: "DELETE" });
    },
  };

  return { auth, db };
}

/** CLI entry point. */
async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    throw new Error("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY first.");
  }
  const deps = supabaseDeps(url, key);

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
    console.log("Existing account — sign out and back in for the role to take effect.");
  }
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e.message || e);
    process.exit(1);
  });
}

module.exports = { parseArgs, grantAdmin, revokeAdmin, supabaseDeps };
