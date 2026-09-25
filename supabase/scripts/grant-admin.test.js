// node --test supabase/scripts/
const test = require("node:test");
const assert = require("node:assert/strict");
const { parseArgs, grantAdmin, revokeAdmin } = require("./grant-admin");

/**
 * In-memory stand-ins for supabaseDeps(). createAdminUser mimics the
 * handle_new_user trigger by writing the admin profile itself.
 */
function fakes({ users = {}, profiles = {} } = {}) {
  const auth = {
    users: { ...users },
    revoked: [],
    async getUserByEmail(email) {
      return Object.values(this.users).find((u) => u.email === email) || null;
    },
    async createAdminUser({ email, name }) {
      const u = { id: `uid-${email}`, email, app_metadata: { role: "admin" } };
      this.users[u.id] = u;
      db.rows[u.id] = { uid: u.id, email, name, role: "admin", created_at: "now" };
      return u;
    },
    async setAdminRole(uid, isAdmin) {
      const meta = { ...this.users[uid].app_metadata };
      if (isAdmin) meta.role = "admin";
      else delete meta.role;
      this.users[uid].app_metadata = meta;
    },
    async revokeSessions(uid) {
      this.revoked.push(uid);
    },
    async generateRecoveryLink(email) {
      return `https://reset/${email}`;
    },
  };
  const db = {
    rows: { ...profiles },
    async getProfile(uid) {
      return this.rows[uid] || null;
    },
    async findAdmins() {
      return Object.values(this.rows).filter((p) => p.role === "admin");
    },
    async upsertProfile(p) {
      this.rows[p.uid] = { ...(this.rows[p.uid] || {}), ...p };
    },
    async deleteProfile(uid) {
      delete this.rows[uid];
    },
  };
  return { auth, db };
}

test("parseArgs normalises the email and rejects junk", () => {
  assert.deepEqual(parseArgs([" Admin@Sellora.App ", "--name", "Ops"]), {
    email: "admin@sellora.app", name: "Ops", revoke: false,
  });
  assert.equal(parseArgs(["a@b.co", "--revoke"]).revoke, true);
  assert.throws(() => parseArgs([]));
  assert.throws(() => parseArgs(["not-an-email"]));
  assert.throws(() => parseArgs(["a@b.co", "--bogus"]));
});

test("grantAdmin creates a new account with role, profile and reset link", async () => {
  const deps = fakes();
  const res = await grantAdmin(deps, { email: "admin@sellora.app", name: "Ops" });
  assert.equal(res.created, true);
  assert.equal(res.resetLink, "https://reset/admin@sellora.app");
  assert.equal(deps.auth.users[res.uid].app_metadata.role, "admin");
  assert.equal(deps.db.rows[res.uid].role, "admin");
  assert.equal(deps.db.rows[res.uid].name, "Ops");
});

test("grantAdmin refuses an email that already belongs to a seller", async () => {
  const deps = fakes({
    users: { s1: { id: "s1", email: "shop@x.com", app_metadata: {} } },
    profiles: { s1: { uid: "s1", role: "seller", email: "shop@x.com" } },
  });
  await assert.rejects(
      grantAdmin(deps, { email: "shop@x.com", name: "x" }),
      /separate email/,
  );
  assert.equal(deps.auth.users.s1.app_metadata.role, undefined);
});

test("grantAdmin refuses a second admin", async () => {
  const deps = fakes({
    users: { a1: { id: "a1", email: "old@x.com", app_metadata: { role: "admin" } } },
    profiles: { a1: { uid: "a1", role: "admin", email: "old@x.com" } },
  });
  await assert.rejects(
      grantAdmin(deps, { email: "new@x.com", name: "x" }),
      /already the admin/,
  );
  assert.equal(Object.keys(deps.auth.users).length, 1);
});

test("grantAdmin is idempotent for the existing admin", async () => {
  const deps = fakes({
    users: { a1: { id: "a1", email: "a@x.com", app_metadata: { role: "admin" } } },
    profiles: { a1: { uid: "a1", role: "admin", email: "a@x.com", created_at: "2026-01-01" } },
  });
  const res = await grantAdmin(deps, { email: "a@x.com", name: "A" });
  assert.equal(res.created, false);
  assert.equal(res.resetLink, null);
  assert.equal(deps.db.rows.a1.created_at, "2026-01-01");
});

test("grantAdmin provisions a profile for an existing account that has none", async () => {
  const deps = fakes({
    users: { d1: { id: "d1", email: "ops@x.com", app_metadata: {} } },
  });
  const res = await grantAdmin(deps, { email: "ops@x.com", name: "Ops" });
  assert.equal(res.created, false);
  assert.equal(deps.auth.users.d1.app_metadata.role, "admin");
  assert.equal(deps.db.rows.d1.role, "admin");
});

test("revokeAdmin drops the role, ends sessions and removes the profile", async () => {
  const deps = fakes({
    users: { a1: { id: "a1", email: "a@x.com", app_metadata: { role: "admin", x: 1 } } },
    profiles: { a1: { uid: "a1", role: "admin" } },
  });
  await revokeAdmin(deps, { email: "a@x.com" });
  assert.deepEqual(deps.auth.users.a1.app_metadata, { x: 1 });
  assert.deepEqual(deps.auth.revoked, ["a1"]);
  assert.equal("a1" in deps.db.rows, false);
});
