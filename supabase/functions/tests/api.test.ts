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
    const db = fakeDb((c: any) => {
      if (c.rpc === "consume_rate_limit") return { data: [{ allowed: true }], error: null };
      if (c.table === "webhook_events") return { data: [], error: null };
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
    });
    setDb(db);
    const res = await call("intasendWebhook", {
      method: "POST",
      body: JSON.stringify({ invoice_id: "INV-SOMEONE-ELSES", api_ref: "order-1", state: "COMPLETE" }),
    });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.success, false);
    assert.match(body.message, /does not belong/);

    // M5: stored before it was acted on, then marked with what happened.
    // deno-lint-ignore no-explicit-any
    const events = db.calls.filter((c: any) => c.table === "webhook_events");
    assert.equal(events[0].op, "upsert");
    assert.equal(events[0].payload.invoice_id, "INV-SOMEONE-ELSES");
    assert.equal(events[0].payload.state, "COMPLETE");
    assert.equal(events[1].op, "update");
    assert.match(events[1].payload.outcome, /does not belong/);
  });

  test("is limited per IP", async () => {
    setDb(fakeDb(() => ({ data: [{ allowed: false, retry_after_ms: 1000 }], error: null })));
    const res = await call("intasendWebhook", {
      method: "POST",
      headers: { "x-forwarded-for": "203.0.113.9" },
      body: JSON.stringify({ invoice_id: "I", api_ref: "o" }),
    });
    assert.equal(res.status, 429);
  });
});

// deno-lint-ignore no-explicit-any
const signedInAs = (respond: (c: any) => any) => {
  const db = fakeDb(respond);
  setDb({
    ...db,
    auth: {
      getUser: () => Promise.resolve({
        data: { user: { id: "buyer-1", email: "b@x.c", app_metadata: {} } },
        error: null,
      }),
    },
  });
  return db;
};

describe("public catalog", () => {
  test("is limited per IP, keyed on the forwarded address", async () => {
    const db = fakeDb(() => ({ data: [{ allowed: false, retry_after_ms: 2000 }], error: null }));
    setDb(db);
    const res = await call("searchProducts?keyword=lamp", {
      headers: { "x-forwarded-for": "198.51.100.7, 10.0.0.1" },
    });
    assert.equal(res.status, 429);
    // deno-lint-ignore no-explicit-any
    assert.equal((db.calls[0] as any).args.p_key, "publicCatalog:ip:198.51.100.7");
  });
});

describe("payments", () => {
  test("an expired order can't start a payment", async () => {
    // deno-lint-ignore no-explicit-any
    signedInAs((c: any) => {
      if (c.rpc) return { data: [{ allowed: true }], error: null };
      return {
        data: {
          id: "order-1",
          buyer_id: "buyer-1",
          status: "pending",
          payment_status: "pending",
          total_kes: 2500,
          expires_at: new Date(Date.now() - 60_000).toISOString(),
        },
        error: null,
      };
    });
    const res = await call("payOrderMpesa", {
      method: "POST",
      headers: { Authorization: "Bearer token" },
      body: JSON.stringify({ orderId: "order-1", phoneNumber: "254712345678" }),
    });
    assert.equal(res.status, 409);
    assert.match((await res.json()).message, /expired/);
  });
});

describe("deleteAccount", () => {
  test("needs a signed-in caller", async () => {
    assert.equal((await call("deleteAccount", { method: "POST", body: "{}" })).status, 401);
  });

  test("is refused while a paid order is still being delivered, and deletes nothing", async () => {
    let authDeleted = false;
    // deno-lint-ignore no-explicit-any
    const db = fakeDb((c: any) => {
      if (c.rpc === "consume_rate_limit") return { data: [{ allowed: true }], error: null };
      if (c.rpc === "delete_account_data") {
        return { data: { deleted: false, reason: "open_orders", openOrders: 1 }, error: null };
      }
      throw new Error(`unexpected ${c.table ?? c.rpc}`);
    });
    setDb({
      ...db,
      auth: {
        getUser: () => Promise.resolve({ data: { user: { id: "buyer-1", app_metadata: {} } }, error: null }),
        admin: { deleteUser: () => { authDeleted = true; return Promise.resolve({ error: null }); } },
      },
    });
    const res = await call("deleteAccount", {
      method: "POST",
      headers: { Authorization: "Bearer token" },
      body: "{}",
    });
    assert.equal(res.status, 409);
    assert.equal((await res.json()).reason, "open_orders");
    assert.equal(authDeleted, false);
  });

  test("scrubs the data, then soft-deletes the Auth user", async () => {
    let deletedWith: unknown[] = [];
    // deno-lint-ignore no-explicit-any
    const db = fakeDb((c: any) => {
      if (c.rpc === "consume_rate_limit") return { data: [{ allowed: true }], error: null };
      if (c.rpc === "delete_account_data") return { data: { deleted: true, role: "buyer" }, error: null };
      throw new Error(`unexpected ${c.table ?? c.rpc}`);
    });
    setDb({
      ...db,
      auth: {
        getUser: () => Promise.resolve({ data: { user: { id: "buyer-1", app_metadata: {} } }, error: null }),
        admin: {
          deleteUser: (...args: unknown[]) => {
            deletedWith = args;
            return Promise.resolve({ error: null });
          },
        },
      },
    });
    const res = await call("deleteAccount", {
      method: "POST",
      headers: { Authorization: "Bearer token" },
      body: "{}",
    });
    assert.equal(res.status, 200);
    assert.deepEqual(deletedWith, ["buyer-1", true]);
  });
});
