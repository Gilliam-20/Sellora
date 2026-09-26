/**
 * The slice of axios the provider clients used, on top of fetch (Edge
 * Functions have no axios). A non-2xx response throws an Error carrying
 * `response: { status, data }`, so the callers' existing
 * `if (err.response)` handling works unchanged.
 * @param {object} options Request.
 * @param {string=} options.method HTTP method, GET by default.
 * @param {string} options.url Absolute URL.
 * @param {object=} options.params Query parameters; undefined/null dropped.
 * @param {*=} options.data JSON body.
 * @param {object=} options.headers Extra headers.
 * @param {number=} options.timeout Milliseconds before aborting.
 * @return {Promise<{status: number, data: *}>} The parsed response.
 */
export async function request({
  method = "GET", url, params, data, headers = {}, timeout = 15000,
}) {
  const target = new URL(url);
  for (const [key, value] of Object.entries(params || {})) {
    if (value !== undefined && value !== null) {
      target.searchParams.set(key, String(value));
    }
  }
  const res = await fetch(target, {
    method,
    headers: { "Content-Type": "application/json", ...headers },
    body: data === undefined ? undefined : JSON.stringify(data),
    signal: AbortSignal.timeout(timeout),
  });
  const text = await res.text();
  let body = text;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    // Not JSON (an HTML error page, say) - keep the text for the log.
  }
  if (!res.ok) {
    const err = new Error(`Request failed with status ${res.status}`);
    err.response = { status: res.status, data: body };
    throw err;
  }
  return { status: res.status, data: body };
}
