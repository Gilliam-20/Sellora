import { millisOf } from "./time.js";

/**
 * Post-purchase tracking: turning CJ's order/logistics responses into the
 * snapshot the storefront renders on its "where is my order" screen.
 *
 * Everything here is pure so it can be tested without CJ or the database -
 * `orders.refreshOrderTracking` does the I/O and writes what these build.
 *
 * CJ's field names for this area are documented but, like the rest of the CJ
 * integration, unverified against a live account. Every parser below is
 * therefore tolerant: an unreadable field yields `null` ("unknown"), never a
 * confident wrong answer such as telling a customer their parcel was
 * delivered.
 */

// Our normalized shipment status, finest-grained state we show a customer.
const SHIPMENT = Object.freeze({
  PENDING: "PENDING", // with CJ, not yet handed to a carrier
  IN_TRANSIT: "IN_TRANSIT",
  OUT_FOR_DELIVERY: "OUT_FOR_DELIVERY",
  DELIVERED: "DELIVERED",
  EXCEPTION: "EXCEPTION", // carrier reported a problem
  CANCELLED: "CANCELLED",
  UNKNOWN: "UNKNOWN",
});

// The order row's own `status`, which the Flutter `OrderStatus` enum
// parses. Deliberately coarser than SHIPMENT: the enum is a client contract
// and adding a value to it would break older builds' `firstWhere` fallback.
const ORDER_STATUS = Object.freeze({
  PROCESSING: "processing",
  SHIPPED: "shipped",
  DELIVERED: "delivered",
  CANCELLED: "cancelled",
});

// Once a shipment reaches one of these there is nothing left to poll for.
const TERMINAL_SHIPMENT_STATUSES = Object.freeze([
  SHIPMENT.DELIVERED,
  SHIPMENT.CANCELLED,
]);

// How long a tracking snapshot stays fresh enough to serve without going
// back to CJ. A parcel's status changes a handful of times over days, so
// polling harder buys nothing and spends our CJ rate limit; the customer can
// still force a refresh, which is what `force` is for.
const TRACKING_REFRESH_INTERVAL_MS = 30 * 60 * 1000; // 30m
// A customer pulling to refresh gets a real CJ call at most this often.
const TRACKING_FORCE_INTERVAL_MS = 60 * 1000; // 1m

/**
 * CJ's order status vocabulary, lowercased and stripped of separators so
 * "IN_CANCEL", "In Cancel" and "incancel" all land on the same entry.
 */
const CJ_ORDER_STATUS = Object.freeze({
  created: SHIPMENT.PENDING,
  unpaid: SHIPMENT.PENDING,
  unshipped: SHIPMENT.PENDING,
  processing: SHIPMENT.PENDING,
  shipped: SHIPMENT.IN_TRANSIT,
  delivered: SHIPMENT.DELIVERED,
  incancel: SHIPMENT.CANCELLED,
  cancelled: SHIPMENT.CANCELLED,
  canceled: SHIPMENT.CANCELLED,
});

/**
 * Keyword -> status for a carrier scan description. Carriers write free text
 * ("Arrived at sorting centre", "Out for delivery"), so matching on keywords
 * is the only portable read of it. Order matters: the first match wins, so
 * the more specific phrases come first.
 */
const EVENT_KEYWORDS = Object.freeze([
  ["out for delivery", SHIPMENT.OUT_FOR_DELIVERY],
  ["with delivery courier", SHIPMENT.OUT_FOR_DELIVERY],
  ["delivered", SHIPMENT.DELIVERED],
  ["signed", SHIPMENT.DELIVERED],
  ["returned", SHIPMENT.EXCEPTION],
  ["return to sender", SHIPMENT.EXCEPTION],
  ["undeliverable", SHIPMENT.EXCEPTION],
  ["failed", SHIPMENT.EXCEPTION],
  ["exception", SHIPMENT.EXCEPTION],
  ["held", SHIPMENT.EXCEPTION],
  ["customs", SHIPMENT.IN_TRANSIT],
  ["arrived", SHIPMENT.IN_TRANSIT],
  ["departed", SHIPMENT.IN_TRANSIT],
  ["in transit", SHIPMENT.IN_TRANSIT],
  ["shipped", SHIPMENT.IN_TRANSIT],
  ["dispatched", SHIPMENT.IN_TRANSIT],
]);

/**
 * @param {*} value Any CJ status value.
 * @return {string} Lowercased, separator-free form for lookup.
 */
function statusKey(value) {
  return String(value == null ? "" : value)
      .toLowerCase()
      .replace(/[\s_-]+/g, "");
}

/**
 * Maps CJ's order status onto our shipment vocabulary.
 * @param {*} raw CJ's `orderStatus` (or `status`) value.
 * @return {string} One of `SHIPMENT`; `UNKNOWN` when it isn't recognized,
 *   which the caller treats as "no information", not "nothing happened".
 */
function normalizeCjOrderStatus(raw) {
  return CJ_ORDER_STATUS[statusKey(raw)] || SHIPMENT.UNKNOWN;
}

/**
 * Classifies one carrier scan from its free-text description.
 * @param {string} description The scan text.
 * @return {string} One of `SHIPMENT`.
 */
function classifyEvent(description) {
  const text = String(description || "").toLowerCase();
  if (!text) return SHIPMENT.UNKNOWN;
  for (const [keyword, status] of EVENT_KEYWORDS) {
    if (text.includes(keyword)) return status;
  }
  return SHIPMENT.UNKNOWN;
}

/**
 * Parses one of CJ's tracking rows into our own event shape.
 *
 * CJ names these fields differently between its logistics endpoints, so each
 * value is read from every name it is known to use.
 * @param {object} row A row from CJ's track-info response.
 * @return {{at: (string|null), description: string, location: (string|null),
 *   status: string}|null} The event, or null if there is nothing readable.
 */
function normalizeTrackEvent(row) {
  if (!row || typeof row !== "object") return null;
  const description = String(
      row.status ?? row.statusDescription ?? row.description ??
      row.context ?? row.remark ?? "").trim();
  const at = row.date ?? row.time ?? row.trackDate ?? row.createDate ?? null;
  if (!description && !at) return null;
  const location = row.location ?? row.area ?? row.address ?? null;
  return {
    at: at == null ? null : String(at),
    description,
    location: location == null ? null : String(location),
    status: classifyEvent(description),
  };
}

/**
 * Normalizes and orders a whole track-info response, newest scan first -
 * which is the order the tracking screen lists them in.
 * @param {*} rows CJ's raw rows (or anything else it returned).
 * @return {Array<object>} Normalized events; empty when nothing parsed.
 */
function normalizeTrackEvents(rows) {
  if (!Array.isArray(rows)) return [];
  const events = rows.map(normalizeTrackEvent).filter(Boolean);
  // Sort by timestamp where we have one, keeping unparseable dates in the
  // order CJ returned them rather than dropping them to the bottom.
  return events.sort((a, b) => {
    const left = Date.parse(a.at || "");
    const right = Date.parse(b.at || "");
    if (Number.isNaN(left) || Number.isNaN(right)) return 0;
    return right - left;
  });
}

/**
 * The shipment status to show, given everything we know.
 *
 * Carrier scans win over CJ's order status when they say something more
 * advanced, because CJ's own status stops updating once a parcel leaves it.
 * @param {object} input Sources.
 * @param {string} input.cjStatus Normalized CJ order status.
 * @param {Array<object>} input.events Normalized carrier events.
 * @param {boolean} input.hasTrackingNumber Whether a number exists yet.
 * @return {string} One of `SHIPMENT`.
 */
function deriveShipmentStatus({ cjStatus, events, hasTrackingNumber }) {
  if (cjStatus === SHIPMENT.CANCELLED) return SHIPMENT.CANCELLED;

  const known = (events || [])
      .map((event) => event.status)
      .filter((status) => status && status !== SHIPMENT.UNKNOWN);
  // Events are newest-first, so the first classified scan is the current one.
  const latest = known[0];
  if (latest === SHIPMENT.DELIVERED) return SHIPMENT.DELIVERED;
  if (latest) return latest;

  if (cjStatus !== SHIPMENT.UNKNOWN) return cjStatus;
  // A tracking number exists but nothing has been scanned yet: the parcel is
  // labelled and waiting for its first carrier scan.
  if (hasTrackingNumber) return SHIPMENT.IN_TRANSIT;
  return SHIPMENT.PENDING;
}

/**
 * The coarse order status written to the order document, which is what the
 * orders list and receipt render.
 * @param {string} shipmentStatus One of `SHIPMENT`.
 * @return {string} One of `ORDER_STATUS`.
 */
function orderStatusFor(shipmentStatus) {
  switch (shipmentStatus) {
    case SHIPMENT.DELIVERED:
      return ORDER_STATUS.DELIVERED;
    case SHIPMENT.CANCELLED:
      return ORDER_STATUS.CANCELLED;
    case SHIPMENT.IN_TRANSIT:
    case SHIPMENT.OUT_FOR_DELIVERY:
    case SHIPMENT.EXCEPTION:
      return ORDER_STATUS.SHIPPED;
    default:
      return ORDER_STATUS.PROCESSING;
  }
}

// How far along the fulfilment journey each order status is. A tracking
// refresh may only move an order forwards: a CJ response that briefly loses
// the tracking number must not walk a shipped order back to "processing"
// under a customer who is already watching the screen.
const ORDER_STATUS_RANK = Object.freeze({
  pending: 0,
  processing: 1,
  shipped: 2,
  delivered: 3,
});

/**
 * The order status to write, given where the order already is.
 * @param {string} current The order's stored `status`.
 * @param {string} derived What this tracking refresh concluded.
 * @return {string|null} The status to write, or null to leave it alone.
 */
function nextOrderStatus(current, derived) {
  if (current === derived) return null;
  // Cancellation is the one status that isn't a step forward, and CJ is
  // authoritative on it - except for a parcel already delivered, where a
  // late cancellation is a data error rather than something the customer
  // should be told about their delivered order.
  if (derived === ORDER_STATUS.CANCELLED) {
    return current === ORDER_STATUS.DELIVERED ? null : ORDER_STATUS.CANCELLED;
  }
  if (current === ORDER_STATUS.CANCELLED) return null;
  const from = ORDER_STATUS_RANK[current] ?? 0;
  const to = ORDER_STATUS_RANK[derived] ?? 0;
  return to > from ? derived : null;
}

/**
 * A public tracking page for a number we have no carrier-specific URL for.
 *
 * CJ ships through dozens of postal partners and doesn't return a tracking
 * link, so an aggregator is the only thing that works for every carrier
 * without maintaining a URL table that silently rots.
 * @param {string} trackingNumber The carrier's number.
 * @return {string|null} A URL, or null when there is no number yet.
 */
function trackingUrlFor(trackingNumber) {
  const number = String(trackingNumber || "").trim();
  if (!number) return null;
  return `https://t.17track.net/en#nums=${encodeURIComponent(number)}`;
}

/**
 * Reads the tracking number out of a CJ order detail response, which names
 * the field differently depending on which endpoint served it.
 * @param {object} cjOrder CJ's order detail payload.
 * @return {string|null} The number, or null when CJ hasn't assigned one.
 */
function extractTrackingNumber(cjOrder) {
  const raw = cjOrder?.trackNumber ?? cjOrder?.trackingNumber ??
      cjOrder?.logisticTrackNumber ?? cjOrder?.trackNo ?? null;
  const number = String(raw == null ? "" : raw).trim();
  return number || null;
}

/**
 * Builds the `tracking` map written onto an order document.
 * @param {object} input Sources.
 * @param {object=} input.cjOrder CJ's order detail payload.
 * @param {Array<object>=} input.events Raw CJ track-info rows.
 * @return {object} The snapshot: shipment status, number, carrier, link,
 *   normalized events, and the coarse order status that goes with it.
 */
function buildTracking({ cjOrder, events }) {
  const cjStatus = normalizeCjOrderStatus(
      cjOrder?.orderStatus ?? cjOrder?.status);
  const trackingNumber = extractTrackingNumber(cjOrder);
  const normalizedEvents = normalizeTrackEvents(events);
  const status = deriveShipmentStatus({
    cjStatus,
    events: normalizedEvents,
    hasTrackingNumber: Boolean(trackingNumber),
  });
  const carrier = cjOrder?.logisticName ?? cjOrder?.shippingType ?? null;
  return {
    status,
    orderStatus: orderStatusFor(status),
    cjStatus: cjOrder?.orderStatus ?? cjOrder?.status ?? null,
    trackingNumber,
    trackingUrl: trackingUrlFor(trackingNumber),
    carrier: carrier == null ? null : String(carrier),
    events: normalizedEvents,
    complete: TERMINAL_SHIPMENT_STATUSES.includes(status),
  };
}

/**
 * Whether an order is worth asking CJ about right now.
 *
 * An order that was never pushed has nothing to track, a delivered or
 * cancelled one has nothing left to learn, and one checked minutes ago would
 * only spend a CJ call to return the same answer.
 * @param {object} order Order document.
 * @param {{now: (number|undefined), force: (boolean|undefined)}=} opts
 *   `force` is a customer-initiated refresh, which uses the shorter window.
 * @return {{refresh: boolean, reason: string}} Decision and why.
 */
function shouldRefreshTracking(
    order, { now = Date.now(), force = false } = {}) {
  if (!order?.cjOrderId) return { refresh: false, reason: "not_pushed" };
  if (order.tracking?.complete) return { refresh: false, reason: "complete" };

  const checkedAt = millisOf(order.trackingCheckedAt);
  const interval = force ?
    TRACKING_FORCE_INTERVAL_MS :
    TRACKING_REFRESH_INTERVAL_MS;
  if (now - checkedAt < interval) return { refresh: false, reason: "fresh" };
  return { refresh: true, reason: "due" };
}

export {
  SHIPMENT,
  ORDER_STATUS,
  TERMINAL_SHIPMENT_STATUSES,
  TRACKING_REFRESH_INTERVAL_MS,
  TRACKING_FORCE_INTERVAL_MS,
  buildTracking,
  classifyEvent,
  deriveShipmentStatus,
  extractTrackingNumber,
  normalizeCjOrderStatus,
  normalizeTrackEvent,
  normalizeTrackEvents,
  nextOrderStatus,
  orderStatusFor,
  shouldRefreshTracking,
  trackingUrlFor,
};
