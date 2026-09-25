const test = require("node:test");
const assert = require("node:assert/strict");
const { parseArgs, grantAdmin, revokeAdmin } = require("../scripts/grant-admin");

/** In-memory stand-ins for the Admin SDK's auth() and firestore(). */
function fakes({ users = {}, docs = {} } = {}) {
  const auth = {
    users: { ...users },
    revoked: [],
    async getUserByEmail(email) {
      const u = Object.values(this.users).find((x) => x.email === email);
      if (!u) throw Object.assign(new Error("nf"), { code: "auth/user-not-found" });
      return u;
    },
    async createUser({ email }) {
      const u = { uid: `uid-${email}`, email, customClaims: {} };
      this.users[u.uid] = u;
      return u;
    },
    async setCustomUserClaims(uid, claims) {
      this.users[uid].customClaims = claims;
    },
    async revokeRefreshTokens(uid) {
      this.revoked.push(uid);
    },
    async generatePasswordResetLink(email) {
      return `https://reset/${email}`;
    },
  };
  const store = { ...docs };
  const snap = (id) => ({ id, exists: id in store, data: () => store[id] });
  const db = {
    store,
    collection: () => ({
      doc: (id) => ({
        get: async () => snap(id),
        set: async (data, { merge } = {}) => {
          store[id] = merge ? { ...(store[id] || {}), ...data } : data;
        },
        delete: async () => {
          delete store[id];
        },
      }),
      where: (field, _op, value) => ({
        get: async () => ({
          docs: Object.keys(store)
              .filter((id) => store[id][field] === value)
              .map(snap),
        }),
      }),
    }),
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

test("grantAdmin creates a new account with claim, profile and reset link", async () => {
  const deps = fakes();
  const res = await grantAdmin(deps, { email: "admin@sellora.app", name: "Ops" });
  assert.equal(res.created, true);
  assert.equal(res.resetLink, "https://reset/admin@sellora.app");
  assert.equal(deps.auth.users[res.uid].customClaims.admin, true);
  assert.equal(deps.db.store[res.uid].role, "admin");
});

test("grantAdmin refuses an email that already belongs to a seller", async () => {
  const deps = fakes({
    users: { s1: { uid: "s1", email: "shop@x.com", customClaims: {} } },
    docs: { s1: { role: "seller", email: "shop@x.com" } },
  });
  await assert.rejects(
      grantAdmin(deps, { email: "shop@x.com", name: "x" }),
      /separate email/,
  );
  assert.equal(deps.auth.users.s1.customClaims.admin, undefined);
});

test("grantAdmin refuses a second admin", async () => {
  const deps = fakes({
    users: { a1: { uid: "a1", email: "old@x.com", customClaims: { admin: true } } },
    docs: { a1: { role: "admin", email: "old@x.com" } },
  });
  await assert.rejects(
      grantAdmin(deps, { email: "new@x.com", name: "x" }),
      /already the admin/,
  );
});

test("grantAdmin is idempotent for the existing admin", async () => {
  const deps = fakes({
    users: { a1: { uid: "a1", email: "a@x.com", customClaims: { admin: true } } },
    docs: { a1: { role: "admin", email: "a@x.com", createdAt: "2026-01-01" } },
  });
  const res = await grantAdmin(deps, { email: "a@x.com", name: "A" });
  assert.equal(res.created, false);
  assert.equal(res.resetLink, null);
  assert.equal(deps.db.store.a1.createdAt, "2026-01-01");
});

test("revokeAdmin drops the claim, signs out sessions and removes the profile", async () => {
  const deps = fakes({
    users: { a1: { uid: "a1", email: "a@x.com", customClaims: { admin: true, x: 1 } } },
    docs: { a1: { role: "admin" } },
  });
  await revokeAdmin(deps, { email: "a@x.com" });
  assert.deepEqual(deps.auth.users.a1.customClaims, { x: 1 });
  assert.deepEqual(deps.auth.revoked, ["a1"]);
  assert.equal("a1" in deps.db.store, false);
});
