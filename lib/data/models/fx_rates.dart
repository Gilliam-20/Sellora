/// A USD-base exchange-rate table — the client-side mirror of the
/// `config/fx` document `functions/lib/fx.js` refreshes once a day
/// (`{base: 'USD', rates: {KES, EUR, GBP}, fetchedAt}`).
///
/// Display-only. The server prices every order from its own copy of these
/// rates and never trusts a client-converted figure, so a stale or fallback
/// table here can only mislabel an estimate, never mis-charge anyone.
class FxRates {
  const FxRates({
    this.base = 'USD',
    required this.rates,
    this.fetchedAt,
  });

  /// Same static values as fx.js's `FALLBACK_RATES`, used until (or if
  /// never) a real rate table loads. They drift with the market.
  static const fallback = FxRates(
    rates: {'KES': 129.0, 'EUR': 0.92, 'GBP': 0.79},
  );

  final String base;

  /// Units of each currency per one [base] unit.
  final Map<String, double> rates;

  /// When the server fetched this table; null for [fallback].
  final DateTime? fetchedAt;

  bool get isFallback => fetchedAt == null;

  /// Multiplier such that `amountIn(from) * rate == amountIn(to)`, pivoting
  /// through [base] when neither side is [base] — the same logic as fx.js's
  /// `pivotRate`. Returns null when a needed rate is missing, rather than
  /// guessing.
  double? rateBetween(String from, String to) {
    if (from == to) return 1;
    if (from == base) return rates[to];
    if (to == base) {
      final r = rates[from];
      return r == null || r == 0 ? null : 1 / r;
    }
    final fromRate = rates[from];
    final toRate = rates[to];
    if (fromRate == null || toRate == null || fromRate == 0) return null;
    return toRate / fromRate;
  }

  /// [map] is the `config/fx` document with `fetchedAt` already converted
  /// to a [DateTime] (or ISO string) by the repository — this model stays
  /// free of Firestore types.
  factory FxRates.fromMap(Map<String, dynamic> map) {
    final raw = Map<String, dynamic>.from(map['rates'] as Map? ?? const {});
    final fetchedAt = map['fetchedAt'];
    return FxRates(
      base: map['base'] as String? ?? 'USD',
      rates: {
        for (final e in raw.entries)
          if (e.value is num) e.key: (e.value as num).toDouble(),
      },
      fetchedAt: fetchedAt is DateTime
          ? fetchedAt
          : fetchedAt is String
              ? DateTime.tryParse(fetchedAt)
              : null,
    );
  }
}
