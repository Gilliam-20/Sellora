#!/usr/bin/env node
/**
 * Checks a real Supabase project against what the repo expects, before and
 * after a rollout (TODO.md, "Supabase migration"):
 *
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node supabase/scripts/preflight.js
 *
 * Reads public.deployment_report() (supabase/migrations/
 * 20260930000100_deployment_report.sql) and the api function's /health, then
 * prints one line per check and exits 1 if any fails. It changes nothing.
 *
 * Needs the service-role (secret) key, like grant-admin.js: run it from a
 * trusted machine only. It never prints a secret, only whether one is set.
 * No npm dependencies: Node 18+'s fetch.
 */
"use strict";

const fs = require("node:fs");
const path = require("node:path");

// Every job a migration schedules. Kept in step with the migrations by
// preflight.test.js.
const EXPECTED_CRON_JOBS = Object.freeze([
  "sellora-expire-orders",
  "sellora-expire-rate-limits",
  "sellora-refresh-fx",
  "sellora-refresh-tracking",
  "sellora-retry-fulfilments",
  "sellora-sync-catalog",
  "sellora-sync-listings",
]);

const VAULT_SECRETS = Object.freeze(["sellora_api_url", "sellora_cron_secret"]);

/**
 * @param {string} dir supabase/migrations.
 * @return {string[]} Migration versions (the filename's leading digits).
 */
function localMigrationVersions(dir) {
  return fs.readdirSync(dir)
      .filter((f) => /^\d+_.*\.sql$/.test(f))
      .map((f) => f.split("_")[0])
      .sort();
}

/**
 * Turns the report into pass/fail lines.
 * @param {object|null} report deployment_report()'s result, or null when the
 *   function doesn't exist yet (the migrations aren't applied).
 * @param {{ok: boolean, detail: string}} health The api function's /health.
 * @param {string[]} localVersions From localMigrationVersions().
 * @return {Array<{name: string, ok: boolean, detail: string}>}
 */
function evaluate(report, health, localVersions) {
  const checks = [];
  const add = (name, ok, detail = "") => checks.push({ name, ok: Boolean(ok), detail });

  add("api Edge Function answers /health", health.ok, health.detail);
  if (!report) {
    add("deployment_report() exists", false,
        "run `npx supabase db push` - the latest migrations aren't applied");
    return checks;
  }

  if (Array.isArray(report.appliedMigrations)) {
    const applied = new Set(report.appliedMigrations.map(String));
    const missing = localVersions.filter((v) => !applied.has(v));
    add("every local migration is applied", missing.length === 0,
        missing.length ? `missing: ${missing.join(", ")} - run \`npx supabase db push\`` : "");
  } else {
    add("every local migration is applied", false, "no migration history table found");
  }

  const extensions = report.extensions || [];
  add("pg_cron and pg_net are enabled",
      extensions.includes("pg_cron") && extensions.includes("pg_net"),
      `enabled: ${extensions.join(", ") || "none"} - enable them under Database > Extensions`);

  const secrets = report.vaultSecrets || [];
  const missingSecrets = VAULT_SECRETS.filter((s) => !secrets.includes(s));
  add("Vault holds the scheduled-job secrets", missingSecrets.length === 0,
      missingSecrets.length ? `missing: ${missingSecrets.join(", ")}` : "");

  const jobs = report.cronJobs || [];
  const missingJobs = EXPECTED_CRON_JOBS.filter((j) => !jobs.includes(j));
  add("every scheduled job exists", missingJobs.length === 0,
      missingJobs.length ?
        `missing: ${missingJobs.join(", ")} - enable pg_cron/pg_net, then re-run the migrations that schedule them` :
        "");
  if (report.cronFailures24h !== null && report.cronFailures24h !== undefined) {
    add("no scheduled job failed in the last 24 hours", report.cronFailures24h === 0,
        `${report.cronFailures24h} failed - see cron.job_run_details and the api function's logs`);
  }

  add("subscription plans are seeded", (report.plans || []).length > 0,
      "insert the plans (Admin > Plans, or SQL) before sellers onboard");
  add("the store-media bucket exists", report.storageBucket === true,
      "apply 20260927000200_storage.sql");
  add("an admin account exists", Number(report.admins) > 0,
      "run scripts/grant-admin.js <email>");
  add("every approved seller has a current subscription",
      Number(report.activeSellersWithoutSubscription) === 0,
      `${report.activeSellersWithoutSubscription} approved seller(s) without one: their storefront is empty and checkout refuses them`);
  return checks;
}

/**
 * @param {string} url Project URL.
 * @param {string} key Service-role key.
 * @return {Promise<{report: (object|null), health: {ok: boolean, detail: string}}>}
 */
async function fetchState(url, key) {
  const base = url.replace(/\/+$/, "");
  const headers = { "apikey": key, "Authorization": `Bearer ${key}`, "Content-Type": "application/json" };

  let report = null;
  const res = await fetch(`${base}/rest/v1/rpc/deployment_report`, {
    method: "POST", headers, body: "{}",
  });
  if (res.ok) {
    report = await res.json();
  } else if (res.status !== 404) {
    throw new Error(`deployment_report failed (${res.status}): ${await res.text()}`);
  }

  let health;
  try {
    const h = await fetch(`${base}/functions/v1/api/health`);
    const body = await h.text();
    health = h.ok && /"ok"/.test(body) ?
      { ok: true, detail: "" } :
      { ok: false, detail: `HTTP ${h.status} - run \`npm run deploy\`` };
  } catch (err) {
    health = { ok: false, detail: String(err.message || err) };
  }
  return { report, health };
}

async function main() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    console.error("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.");
    process.exit(2);
  }
  const { report, health } = await fetchState(url, key);
  const checks = evaluate(report, health,
      localMigrationVersions(path.join(__dirname, "..", "migrations")));
  for (const c of checks) {
    console.log(`${c.ok ? "ok  " : "FAIL"} ${c.name}${!c.ok && c.detail ? `\n       ${c.detail}` : ""}`);
  }
  console.log("\nNot checkable from here: the api function's secrets " +
    "(CJ_API_KEY, INTASEND_SECRET_KEY, CRON_SECRET, INTASEND_WEBHOOK_CHALLENGE) " +
    "and the IntaSend webhook URL. See TODO.md.");
  process.exit(checks.every((c) => c.ok) ? 0 : 1);
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err.message || err);
    process.exit(1);
  });
}

module.exports = { evaluate, localMigrationVersions, EXPECTED_CRON_JOBS };
