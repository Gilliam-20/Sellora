import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  SHIPMENT,
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
} from "../_shared/tracking.js";

const timestamp = (millis) => new Date(millis).toISOString();
const NOW = 1_700_000_000_000;

describe("normalizeCjOrderStatus", () => {
  test("reads CJ's statuses whatever casing or separator they arrive in", () => {
    assert.equal(normalizeCjOrderStatus("UNSHIPPED"), SHIPMENT.PENDING);
    assert.equal(normalizeCjOrderStatus("Shipped"), SHIPMENT.IN_TRANSIT);
    assert.equal(normalizeCjOrderStatus("IN_CANCEL"), SHIPMENT.CANCELLED);
    assert.equal(normalizeCjOrderStatus("in cancel"), SHIPMENT.CANCELLED);
    assert.equal(normalizeCjOrderStatus("DELIVERED"), SHIPMENT.DELIVERED);
  });

  test("an unrecognized status is unknown, not a guess", () => {
    assert.equal(normalizeCjOrderStatus("SOMETHING_NEW"), SHIPMENT.UNKNOWN);
    assert.equal(normalizeCjOrderStatus(undefined), SHIPMENT.UNKNOWN);
    assert.equal(normalizeCjOrderStatus(null), SHIPMENT.UNKNOWN);
  });
});

describe("classifyEvent", () => {
  test("classifies the scans that decide what the customer is told", () => {
    assert.equal(classifyEvent("Delivered, signed by resident"), SHIPMENT.DELIVERED);
    assert.equal(classifyEvent("Out for delivery"), SHIPMENT.OUT_FOR_DELIVERY);
    assert.equal(classifyEvent("Arrived at sorting centre"), SHIPMENT.IN_TRANSIT);
    assert.equal(classifyEvent("Held in customs"), SHIPMENT.EXCEPTION);
    assert.equal(classifyEvent("Return to sender"), SHIPMENT.EXCEPTION);
  });

  test("prefers the more specific phrase over a substring of it", () => {
    // "out for delivery" contains "delivery" but must not read as delivered.
    assert.equal(classifyEvent("Out for delivery with courier"), SHIPMENT.OUT_FOR_DELIVERY);
  });

  test("unrecognized free text is unknown rather than progress", () => {
    assert.equal(classifyEvent("Electronic information submitted"), SHIPMENT.UNKNOWN);
    assert.equal(classifyEvent(""), SHIPMENT.UNKNOWN);
  });
});

describe("normalizeTrackEvent", () => {
  test("reads a row whichever names CJ used for its fields", () => {
    assert.deepEqual(
        normalizeTrackEvent({
          status: "Arrived at facility",
          date: "2026-09-02 08:11:00",
          location: "Nairobi",
        }),
        {
          at: "2026-09-02 08:11:00",
          description: "Arrived at facility",
          location: "Nairobi",
          status: SHIPMENT.IN_TRANSIT,
        },
    );
    assert.equal(
        normalizeTrackEvent({ context: "Delivered", trackDate: "2026-09-05" }).status,
        SHIPMENT.DELIVERED,
    );
  });

  test("drops a row with neither a description nor a date", () => {
    assert.equal(normalizeTrackEvent({}), null);
    assert.equal(normalizeTrackEvent(null), null);
    assert.equal(normalizeTrackEvent("nonsense"), null);
  });
});

describe("normalizeTrackEvents", () => {
  test("orders scans newest first - the screen leads with the latest", () => {
    const events = normalizeTrackEvents([
      { status: "Shipped", date: "2026-09-01 10:00:00" },
      { status: "Delivered", date: "2026-09-05 09:00:00" },
      { status: "Arrived at facility", date: "2026-09-03 12:00:00" },
    ]);
    assert.deepEqual(events.map((e) => e.description), [
      "Delivered",
      "Arrived at facility",
      "Shipped",
    ]);
  });

  test("a non-array response yields no events rather than throwing", () => {
    assert.deepEqual(normalizeTrackEvents(null), []);
    assert.deepEqual(normalizeTrackEvents({ message: "no data" }), []);
  });
});

describe("deriveShipmentStatus", () => {
  test("carrier scans win over CJ's status, which stops updating after dispatch", () => {
    const status = deriveShipmentStatus({
      cjStatus: SHIPMENT.IN_TRANSIT,
      events: [{ status: SHIPMENT.DELIVERED }, { status: SHIPMENT.IN_TRANSIT }],
      hasTrackingNumber: true,
    });
    assert.equal(status, SHIPMENT.DELIVERED);
  });

  test("skips unclassified scans to find the latest one that means something", () => {
    const status = deriveShipmentStatus({
      cjStatus: SHIPMENT.UNKNOWN,
      events: [{ status: SHIPMENT.UNKNOWN }, { status: SHIPMENT.OUT_FOR_DELIVERY }],
      hasTrackingNumber: true,
    });
    assert.equal(status, SHIPMENT.OUT_FOR_DELIVERY);
  });

  test("a tracking number with no scans yet reads as in transit, not pending", () => {
    assert.equal(
        deriveShipmentStatus({
          cjStatus: SHIPMENT.UNKNOWN,
          events: [],
          hasTrackingNumber: true,
        }),
        SHIPMENT.IN_TRANSIT,
    );
  });

  test("nothing known at all is pending, never delivered", () => {
    assert.equal(
        deriveShipmentStatus({
          cjStatus: SHIPMENT.UNKNOWN,
          events: [],
          hasTrackingNumber: false,
        }),
        SHIPMENT.PENDING,
    );
  });

  test("a cancelled CJ order overrides any scan history", () => {
    assert.equal(
        deriveShipmentStatus({
          cjStatus: SHIPMENT.CANCELLED,
          events: [{ status: SHIPMENT.IN_TRANSIT }],
          hasTrackingNumber: true,
        }),
        SHIPMENT.CANCELLED,
    );
  });
});

describe("orderStatusFor", () => {
  test("maps the shipment vocabulary onto the client's OrderStatus enum", () => {
    assert.equal(orderStatusFor(SHIPMENT.PENDING), "processing");
    assert.equal(orderStatusFor(SHIPMENT.IN_TRANSIT), "shipped");
    assert.equal(orderStatusFor(SHIPMENT.OUT_FOR_DELIVERY), "shipped");
    assert.equal(orderStatusFor(SHIPMENT.EXCEPTION), "shipped");
    assert.equal(orderStatusFor(SHIPMENT.DELIVERED), "delivered");
    assert.equal(orderStatusFor(SHIPMENT.CANCELLED), "cancelled");
    assert.equal(orderStatusFor(SHIPMENT.UNKNOWN), "processing");
  });
});

describe("nextOrderStatus", () => {
  test("moves an order forward", () => {
    assert.equal(nextOrderStatus("paid", "shipped"), "shipped");
    assert.equal(nextOrderStatus("shipped", "delivered"), "delivered");
  });

  test("never walks an order backwards on a momentarily thinner CJ response", () => {
    assert.equal(nextOrderStatus("shipped", "processing"), null);
    assert.equal(nextOrderStatus("delivered", "shipped"), null);
  });

  test("leaves an unchanged status alone rather than rewriting it", () => {
    assert.equal(nextOrderStatus("shipped", "shipped"), null);
  });

  test("cancellation applies out of order, except to a delivered parcel", () => {
    assert.equal(nextOrderStatus("shipped", "cancelled"), "cancelled");
    assert.equal(nextOrderStatus("delivered", "cancelled"), null);
  });

  test("a cancelled order isn't revived by a later scan", () => {
    assert.equal(nextOrderStatus("cancelled", "shipped"), null);
  });
});

describe("extractTrackingNumber / trackingUrlFor", () => {
  test("reads the number under each name CJ uses for it", () => {
    assert.equal(extractTrackingNumber({ trackNumber: "LP123" }), "LP123");
    assert.equal(extractTrackingNumber({ trackingNumber: "LP123" }), "LP123");
    assert.equal(extractTrackingNumber({ logisticTrackNumber: "LP123" }), "LP123");
  });

  test("an empty or whitespace number is no number", () => {
    assert.equal(extractTrackingNumber({ trackNumber: "   " }), null);
    assert.equal(extractTrackingNumber({}), null);
    assert.equal(extractTrackingNumber(null), null);
  });

  test("builds a tracking link only when there is something to track", () => {
    assert.equal(trackingUrlFor("LP123"), "https://t.17track.net/en#nums=LP123");
    assert.equal(trackingUrlFor(""), null);
    assert.equal(trackingUrlFor(null), null);
  });
});

describe("buildTracking", () => {
  test("builds the snapshot the tracking screen renders", () => {
    const tracking = buildTracking({
      cjOrder: {
        orderStatus: "SHIPPED",
        trackNumber: "LP00123456789",
        logisticName: "CJPacket Ordinary",
      },
      events: [
        { status: "Shipped from warehouse", date: "2026-09-01 10:00:00" },
        { status: "Arrived at destination country", date: "2026-09-04 06:00:00" },
      ],
    });
    assert.equal(tracking.status, SHIPMENT.IN_TRANSIT);
    assert.equal(tracking.orderStatus, "shipped");
    assert.equal(tracking.trackingNumber, "LP00123456789");
    assert.equal(tracking.carrier, "CJPacket Ordinary");
    assert.equal(tracking.trackingUrl, "https://t.17track.net/en#nums=LP00123456789");
    assert.equal(tracking.complete, false);
    assert.equal(tracking.events.length, 2);
    assert.equal(tracking.events[0].description, "Arrived at destination country");
  });

  test("marks a delivered parcel complete so it stops being polled", () => {
    const tracking = buildTracking({
      cjOrder: { orderStatus: "DELIVERED", trackNumber: "LP1" },
      events: [{ status: "Delivered", date: "2026-09-05 09:00:00" }],
    });
    assert.equal(tracking.status, SHIPMENT.DELIVERED);
    assert.equal(tracking.complete, true);
  });

  test("an order CJ hasn't shipped yet is pending, with no invented link", () => {
    const tracking = buildTracking({ cjOrder: { orderStatus: "UNSHIPPED" }, events: [] });
    assert.equal(tracking.status, SHIPMENT.PENDING);
    assert.equal(tracking.trackingNumber, null);
    assert.equal(tracking.trackingUrl, null);
    assert.equal(tracking.complete, false);
  });

  test("survives a CJ response in a shape we don't recognize at all", () => {
    const tracking = buildTracking({ cjOrder: {}, events: "nope" });
    assert.equal(tracking.status, SHIPMENT.PENDING);
    assert.equal(tracking.orderStatus, "processing");
    assert.deepEqual(tracking.events, []);
    assert.equal(tracking.complete, false);
  });
});

describe("shouldRefreshTracking", () => {
  const pushed = {
    cjOrderId: "cj-1",
    trackingCheckedAt: timestamp(NOW - TRACKING_REFRESH_INTERVAL_MS - 1),
  };

  test("refreshes an order that has never been checked", () => {
    assert.deepEqual(
        shouldRefreshTracking({ cjOrderId: "cj-1" }, { now: NOW }),
        { refresh: true, reason: "due" },
    );
  });

  test("refreshes once the snapshot is past its interval", () => {
    assert.equal(shouldRefreshTracking(pushed, { now: NOW }).refresh, true);
  });

  test("an order never pushed to CJ has nothing to track", () => {
    const decision = shouldRefreshTracking({ cjOrderId: null }, { now: NOW });
    assert.deepEqual(decision, { refresh: false, reason: "not_pushed" });
  });

  test("a delivered order is never polled again", () => {
    const decision = shouldRefreshTracking(
        { cjOrderId: "cj-1", tracking: { complete: true } }, { now: NOW });
    assert.deepEqual(decision, { refresh: false, reason: "complete" });
  });

  test("a recently-checked order isn't re-asked", () => {
    const decision = shouldRefreshTracking(
        { cjOrderId: "cj-1", trackingCheckedAt: timestamp(NOW - 60_000) },
        { now: NOW });
    assert.deepEqual(decision, { refresh: false, reason: "fresh" });
  });

  test("a customer pull-to-refresh uses the shorter window but still has one", () => {
    const recent = {
      cjOrderId: "cj-1",
      trackingCheckedAt: timestamp(NOW - TRACKING_FORCE_INTERVAL_MS - 1),
    };
    assert.equal(shouldRefreshTracking(recent, { now: NOW, force: true }).refresh, true);
    assert.equal(
        shouldRefreshTracking(
            { cjOrderId: "cj-1", trackingCheckedAt: timestamp(NOW - 5_000) },
            { now: NOW, force: true }).refresh,
        false,
    );
  });
});
