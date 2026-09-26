// node --test supabase/scripts/
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { evaluate, localMigrationVersions, EXPECTED_CRON_JOBS } = require("./preflight");

const migrations = path.join(__dirname, "..", "migrations");
const healthy = { ok: true, detail: "" };

/** A project where everything is in place. */
function goodReport(overrides = {}) {
  return {
    appliedMigrations: localMigrationVersions(migrations),
    vaultSecrets: ["sellora_api_url", "sellora_cron_secret"],
    extensions: ["pg_cron", "pg_net"],
    cronJobs: [...EXPECTED_CRON_JOBS],
    cronFailures24h: 0,
    plans: ["starter", "growth"],
    storageBucket: true,
    admins: 1,
    activeSellersWithoutSubscription: 0,
    ...overrides,
  };
}

const failing = (checks) => checks.filter((c) => !c.ok).map((c) => c.name);

test("a fully rolled-out project passes every check", () => {
  const checks = evaluate(goodReport(), healthy, localMigrationVersions(migrations));
  assert.deepEqual(failing(checks), []);
});

test("the expected cron jobs are exactly the ones the migrations schedule", () => {
  const scheduled = new Set();
  for (const f of fs.readdirSync(migrations)) {
    const sql = fs.readFileSync(path.join(migrations, f), "utf8");
    for (const m of sql.matchAll(/cron\.schedule\('([a-z-]+)'/g)) scheduled.add(m[1]);
  }
  assert.deepEqual([...scheduled].sort(), [...EXPECTED_CRON_JOBS].sort());
});

test("names the migrations still to push", () => {
  const local = localMigrationVersions(migrations);
  const checks = evaluate(goodReport({ appliedMigrations: local.slice(0, -2) }), healthy, local);
  const c = checks.find((x) => x.name === "every local migration is applied");
  assert.equal(c.ok, false);
  assert.match(c.detail, new RegExp(local.at(-1)));
});

test("an unapplied report function stops at that, with the fix", () => {
  const checks = evaluate(null, healthy, []);
  assert.deepEqual(failing(checks), ["deployment_report() exists"]);
  assert.match(checks[1].detail, /db push/);
});

test("flags each missing piece of setup", () => {
  const checks = evaluate(goodReport({
    vaultSecrets: ["sellora_api_url"],
    cronJobs: EXPECTED_CRON_JOBS.slice(1),
    cronFailures24h: 3,
    plans: [],
    admins: 0,
    activeSellersWithoutSubscription: 2,
  }), { ok: false, detail: "HTTP 404" }, localMigrationVersions(migrations));
  assert.deepEqual(failing(checks), [
    "api Edge Function answers /health",
    "Vault holds the scheduled-job secrets",
    "every scheduled job exists",
    "no scheduled job failed in the last 24 hours",
    "subscription plans are seeded",
    "an admin account exists",
    "every approved seller has a current subscription",
  ]);
  assert.match(checks.find((c) => c.name.startsWith("Vault")).detail, /sellora_cron_secret/);
  assert.ok(!checks.some((c) => /sellora_api_url/.test(c.detail)));
});
