import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { checkRateLimit, clientKey, POLICIES } from "../_shared/rateLimit.js";
import { setLogSink } from "../_shared/logging.js";
import { fakeDb } from "./fakeDb.js";

// The window arithmetic itself lives in the consume_rate_limit SQL function
// and is tested in PGlite (supabase/tests/rls.test.mjs). This covers the
// client side: what it asks for, and how it reads the answer.

describe("checkRateLimit", () => {
  test("asks for the policy's budget under a per-user key", async () => {
    const client = fakeDb(() => ({ data: [{ allowed: true, retry_after_ms: 0 }], error: null }));
    const result = await checkRateLimit("createOrder", "user-1", { client });
    assert.deepEqual(result, { allowed: true, retryAfterMs: 0 });
    assert.deepEqual(client.calls[0], {
      rpc: "consume_rate_limit",
      args: {
        p_key: "createOrder:user-1",
        p_limit: POLICIES.createOrder.limit,
        p_window_ms: POLICIES.createOrder.windowMs,
      },
    });
  });

  test("passes a refusal and its retry-after through", async () => {
    const client = fakeDb(() => ({ data: [{ allowed: false, retry_after_ms: 4200 }], error: null }));
    assert.deepEqual(
        await checkRateLimit("mpesaPush", "user-1", { client }),
        { allowed: false, retryAfterMs: 4200 });
  });

  test("fails open when the database errors - a limiter outage must not stop checkout", async () => {
    const logged = [];
    const previous = setLogSink({ info() {}, warn: (line) => logged.push(line), error() {} });
    try {
      const client = fakeDb(() => ({ data: null, error: { message: "connection refused" } }));
      assert.deepEqual(
          await checkRateLimit("createOrder", "user-1", { client }),
          { allowed: true, retryAfterMs: 0 });
      assert.match(logged[0], /rate_limit_unavailable/);
    } finally {
      setLogSink(previous);
    }
  });

  test("rejects an unknown policy - a typo must not silently mean unlimited", async () => {
    await assert.rejects(checkRateLimit("nope", "user-1", { client: fakeDb(() => ({})) }));
  });
});

describe("clientKey", () => {
  const request = (headers) => new Request("http://localhost/", { headers });

  test("keys a public caller on the first x-forwarded-for hop", () => {
    assert.equal(clientKey(request({ "x-forwarded-for": "41.90.1.2, 10.0.0.1" })), "ip:41.90.1.2");
  });

  test("falls back to x-real-ip, then to a shared unknown bucket", () => {
    assert.equal(clientKey(request({ "x-real-ip": "41.90.1.3" })), "ip:41.90.1.3");
    assert.equal(clientKey(request({})), "ip:unknown");
  });

  test("caps a forged header's length - it becomes a database key", () => {
    assert.equal(clientKey(request({ "x-forwarded-for": "x".repeat(500) })).length, "ip:".length + 64);
  });
});
