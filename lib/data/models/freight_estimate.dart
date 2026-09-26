/// The cheapest CJ freight option for a destination, picked the same way
/// supabase/functions/_shared/orders.js already does server-side (lowest `logisticPrice`
/// among the options `calculateFreight` returns).
///
/// Only `logisticPrice`/`logisticName` are contract-confirmed anywhere in
/// this repo — no delivery-time field is surfaced since none is tested.
class FreightEstimate {
  FreightEstimate({
    required this.cost,
    required this.logisticName,
    this.currency = 'USD',
  });

  final double cost;
  final String logisticName;
  final String currency;
}

/// One CJ shipping line for a cart, as returned (unfiltered) by
/// `calculateFreight` — unlike [FreightEstimate], which collapses CJ's
/// options down to the cheapest, this carries every option CJ offered so the
/// buyer can pick a shipment type at checkout. `logisticName` is the only
/// field `supabase/functions/_shared/orders.js`'s `createOrder` accepts back from the
/// client — it re-derives the price itself from CJ's own quote rather than
/// trusting [cost].
class FreightOption {
  FreightOption({
    required this.logisticName,
    required this.cost,
    this.currency = 'USD',
    this.estimatedDelivery,
  });

  final String logisticName;
  final double cost;
  final String currency;

  /// CJ's own transit-time string for this line (e.g. "7-15 days"), when it
  /// sends one — not contract-confirmed against a real CJ account, so this
  /// stays null rather than guessing at a field name.
  final String? estimatedDelivery;
}
