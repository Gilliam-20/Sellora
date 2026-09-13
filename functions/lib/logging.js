const logger = require("firebase-functions/logger");

/**
 * Structured logging for Cloud Logging.
 *
 * Every entry carries an `event` field, and the ones worth waking someone up
 * for also carry `alert: true`. Log-based alert policies are defined against
 * exactly those two fields, so renaming either - or an ALERTS value - silently
 * disables the alert that watches it. See TODO.md Phase 3 for the alert list.
 */

const ALERTS = Object.freeze({
  CJ_PUSH_FAILED: "cj_push_failed",
  ORDER_NEEDS_RECONCILIATION: "order_needs_reconciliation",
  WEBHOOK_SIGNATURE_INVALID: "webhook_signature_invalid",
  PAYMENT_AMOUNT_MISMATCH: "payment_amount_mismatch",
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
 * Builds the payload written to Cloud Logging's jsonPayload. Exported for
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
  logger.info(event, buildEntry(event, fields));
}

/** Something degraded but handled - no one needs to be paged. */
function logWarning(event, fields, error) {
  logger.warn(event, buildEntry(event, fields, { error }));
}

/** A failure. Carries the context needed to debug it without a redeploy. */
function logError(event, fields, error) {
  logger.error(event, buildEntry(event, fields, { error }));
}

/**
 * A failure someone must act on - money or fulfillment is affected. Alert
 * policies watch `jsonPayload.alert = true`.
 * @param {string} event One of `ALERTS`.
 * @param {object=} fields Context, e.g. `{ orderId, uid }`.
 * @param {Error=} error Underlying error, if there is one.
 */
function logAlert(event, fields, error) {
  logger.error(event, buildEntry(event, fields, { alert: true, error }));
}

module.exports = { ALERTS, buildEntry, logInfo, logWarning, logError, logAlert };
