/// The cheapest CJ freight option for a destination, picked the same way
/// functions/lib/orders.js already does server-side (lowest `logisticPrice`
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
