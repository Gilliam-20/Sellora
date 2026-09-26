/**
 * Structured logging for the Edge Function logs.
 *
 * Each entry is one JSON line on stdout/stderr, which Supabase's function
 * logs (Dashboard -> Edge Functions -> Logs, or the `function_logs` source in
 * Logs Explorer) keep as the event message. Every entry carries an `event`
 * field, and the ones worth waking someone up for also carry `alert: true`
 * - search or alert on exactly those two fields, so renaming either, or an
 * ALERTS value, silently disables whatever watches it.
 */

// Swappable for tests, which assert on what would have been written.
let sink = {
  info: (line) => console.log(line),
  warn: (line) => console.warn(line),
  error: (line) => console.error(line),
};

/**
 * Replaces where entries are written. For tests.
 * @param {{info: Function, warn: Function, error: Function}} next New sink.
 * @return {object} The previous sink, to restore afterwards.
 */
function setLogSink(next) {
  const previous = sink;
  sink = next;
  return previous;
}

/**
 * @param {string} level Severity.
 * @param {object} entry Payload from `buildEntry`.
 * @return {string} The JSON line.
 */
function line(level, entry) {
  return JSON.stringify({ level, ...entry });
}

const ALERTS = Object.freeze({
  CJ_PUSH_FAILED: "cj_push_failed",
  ORDER_NEEDS_RECONCILIATION: "order_needs_reconciliation",
  WEBHOOK_SIGNATURE_INVALID: "webhook_signature_invalid",
  PAYMENT_AMOUNT_MISMATCH: "payment_amount_mismatch",
  // IntaSend's status response had no amount we could read. The payment is
  // held, not fulfilled - most likely the response shape, not fraud.
  PAYMENT_AMOUNT_UNVERIFIED: "payment_amount_unverified",
  FX_FALLBACK: "fx_fallback",
  FX_STALE: "fx_stale",
  DELIVERY_EXCEPTION: "delivery_exception",
  REFUND_FAILED: "refund_failed",
});

// Long free-text values (a CJ error body, a keyword) are truncated so one bad
// response can't blow up a log entry.
const MAX_VALUE_LENGTH = 1000;

/**
 * Drops empty fields and truncates long strings, so an entry only carries
 * values that are actually useful to filter or read.
 * @param {object} fields Raw fields.
 * @return {object} Cleaned fields.
 */
function clean(fields) {
  const result = {};
  for (const [key, value] of Object.entries(fields || {})) {
    if (value === undefined || value === null || value === "") continue;
    result[key] = typeof value === "string" && value.length > MAX_VALUE_LENGTH ?
      `${value.slice(0, MAX_VALUE_LENGTH)}...` :
      value;
  }
  return result;
}

/**
 * Builds the structured payload of one log line. Exported for
 * tests; handlers should call the log* functions below instead.
 * @param {string} event Event name - the field alerts filter on.
 * @param {object=} fields Context, e.g. `{ orderId, uid, endpoint }`.
 * @param {{alert: (boolean|undefined), error: (Error|undefined)}=} opts
 *   `alert` marks the entry as alert-worthy; `error` attaches its message.
 * @return {object} The structured payload.
 */
function buildEntry(event, fields = {}, opts = {}) {
  const entry = { event, ...clean(fields) };
  if (opts.alert) entry.alert = true;
  if (opts.error) {
    entry.error = String(opts.error.message || opts.error).slice(0, MAX_VALUE_LENGTH);
  }
  return entry;
}

/** Routine event worth being able to search for later. */
function logInfo(event, fields) {
  sink.info(line("info", buildEntry(event, fields)));
}

/** Something degraded but handled - no one needs to be paged. */
function logWarning(event, fields, error) {
  sink.warn(line("warning", buildEntry(event, fields, { error })));
}

/** A failure. Carries the context needed to debug it without a redeploy. */
function logError(event, fields, error) {
  sink.error(line("error", buildEntry(event, fields, { error })));
}

/**
 * A failure someone must act on - money or fulfillment is affected. Alerts
 * watch for `"alert":true`.
 * @param {string} event One of `ALERTS`.
 * @param {object=} fields Context, e.g. `{ orderId, uid }`.
 * @param {Error=} error Underlying error, if there is one.
 */
function logAlert(event, fields, error) {
  sink.error(line("error", buildEntry(event, fields, { alert: true, error })));
}

export { ALERTS, buildEntry, setLogSink, logInfo, logWarning, logError, logAlert };
