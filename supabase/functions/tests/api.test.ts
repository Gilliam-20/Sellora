import { afterEach, describe, test } from "node:test";
import assert from "node:assert/strict";
import { handle, routeOf } from "../api/handler.ts";
import { setDb } from "../_shared/db.js";
import { fakeDb } from "./fakeDb.js";

const call = (path: string, init: RequestInit = {}) =>
  handle(new Request(`http://localhost/functions/v1/api/${path}`, init));

afterEach(() => {
  setDb(null);
  Deno.env.delete("CRON_SECRET");
});

describe("routing", () => {
  test("strips everything up to the function name", () => {
    assert.equal(routeOf("/api/createOrder"), "createOrder");
    assert.equal(routeOf("/functions/v1/api/cron/syncCatalog"), "cron/syncCatalog");
  });

  test("answers CORS preflights for the web build", async () => {
    const res = await call("createOrder", { method: "OPTIONS" });
    assert.equal(res.status, 200);
    assert.match(res.headers.get("Access-Control-Allow-Headers") ?? "", /authorization/);
  });

  test("health needs no auth", async () => {
    const res = await call("health");
    assert.deepEqual(await res.json(), { status: "ok" });
  });

  test("unknown routes are 404, wrong methods 405", async () => {
    assert.equal((await call("nope")).status, 404);
    assert.equal((await call("createOrder")).status, 405);
    assert.equal((await call("searchProducts", { method: "POST" })).status, 405);
  });
});

describe("auth", () => {
  test("signed-in routes refuse a request with no token", async () => {
    const res = await call("createOrder", { method: "POST", body: "{}" });
    assert.equal(res.status, 401);
    assert.equal((await res.json()).success, false);
    assert.equal(res.headers.get("Access-Control-Allow-Origin"), "*");
  });

  test("a token Supabase Auth rejects is refused", async () => {
    setDb({ auth: { getUser: () => Promise.resolve({ data: { user: null }, error: { message: "bad jwt" } }) } });
    const res = await call("subscribeSeller", {
      method: "POST",
      headers: { Authorization: "Bearer forged" },
      body: JSON.stringify({ planId: "starter" }),
    });
    assert.equal(res.status, 401);
  });

  test("admin routes refuse a signed-in non-admin", async () => {
    setDb({
      auth: {
        getUser: () => Promise.resolve({
          data: { user: { id: "u1", email: "a@b.c", app_metadata: {} } },
          error: null,
        }),
      },
    });
    const res = await call("runCatalogSync", {
      method: "POST",
      headers: { Authorization: "Bearer token" },
    });
    assert.equal(res.status, 403);
  });

  test("a banned user's token is refused", async () => {
    setDb({
      auth: {
        getUser: () => Promise.resolve({
          data: {
            user: {
              id: "u1",
              app_metadata: { role: "admin" },
              banned_until: new Date(Date.now() + 3600_000).toISOString(),
            },
          },
          error: null,
        }),
      },
    });
    const res = await call("runCatalogSync", {
      method: "POST",
      headers: { Authorization: "Bearer token" },
    });
    assert.equal(res.status, 401);
  });

  test("a spent rate limit answers 429 with Retry-After", async () => {
    const db = fakeDb(() => ({ data: [{ allowed: false, retry_after_ms: 2500 }], error: null }));
    setDb({
      ...db,
      auth: {
        getUser: () => Promise.resolve({ data: { user: { id: "u1", app_metadata: {} } }, error: null }),
      },
    });
    const res = await call("createOrder", {
      method: "POST",
      headers: { Authorization: "Bearer token" },
      body: "{}",
    });
    assert.equal(res.status, 429);
    assert.equal(res.headers.get("Retry-After"), "3");
  });
});

describe("cron", () => {
  test("refuses a job without the shared secret", async () => {
    Deno.env.set("CRON_SECRET", "s3cret");
    const res = await call("cron/refreshFxRate", {
      method: "POST",
      headers: { "x-cron-secret": "wrong" },
    });
    assert.equal(res.status, 401);
  });

  test("refuses every job when no secret is configured", async () => {
    const res = await call("cron/refreshFxRate", {
      method: "POST",
      headers: { "x-cron-secret": "" },
    });
    assert.equal(res.status, 401);
  });

  test("an unknown job is 404 even with the secret", async () => {
    Deno.env.set("CRON_SECRET", "s3cret");
    const res = await call("cron/dropTables", {
      method: "POST",
      headers: { "x-cron-secret": "s3cret" },
    });
    assert.equal(res.status, 404);
  });
});

describe("intasendWebhook", () => {
  test("rejects a payload without invoice_id/api_ref", async () => {
    const res = await call("intasendWebhook", { method: "POST", body: JSON.stringify({}) });
    assert.equal(res.status, 400);
  });

  test("never lets a stray invoice pay for someone else's order", async () => {
    // deno-lint-ignore no-explicit-any
    setDb(fakeDb((c: any) => {
      if (c.table === "billing_history") return { data: null, error: null };
      if (c.table === "orders") {
        return {
          data: {
            id: "order-1",
            buyer_id: "buyer-1",
            payment_ref: { invoiceId: "INV-MINE" },
            payment_attempts: [],
          },
          error: null,
        };
      }
      throw new Error(`unexpected ${c.table}`);
    }));
    const res = await call("intasendWebhook", {
      method: "POST",
      body: JSON.stringify({ invoice_id: "INV-SOMEONE-ELSES", api_ref: "order-1" }),
    });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.success, false);
    assert.match(body.message, /does not belong/);
  });
});
