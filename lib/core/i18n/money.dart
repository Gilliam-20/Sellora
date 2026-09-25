import 'currencies.dart';

/// An amount of one currency, held as an integer count of that currency's
/// minor unit (cents, pence, KES cents) — the build spec's §36 "use integer
/// minor units" rule. Summing doubles drifts (`0.1 + 0.2 != 0.3`); summing ints
/// doesn't, and every operation that can't stay exact ([scale],
/// [convertTo]) rounds once, explicitly, back to a whole minor unit.
///
/// Models still store `double` major-unit amounts (a Firestore/server
/// migration to minor units is a separate, larger change), so the usual
/// pattern is: lift with [Money.fromMajor], do the arithmetic here, and
/// drop back with [toMajor] at the edge.
class Money implements Comparable<Money> {
  const Money(this.minorUnits, this.currency);

  Money.zero(this.currency) : minorUnits = 0;

  /// Rounds [amount] half away from zero to [currency]'s minor unit.
  factory Money.fromMajor(double amount, String currency) =>
      Money(_roundToMinor(amount, _factor(currency)), currency);

  /// Sum of [values], all of which must be in [currency].
  factory Money.sum(Iterable<Money> values, String currency) =>
      values.fold(Money.zero(currency), (sum, m) => sum + m);

  final int minorUnits;
  final String currency;

  double toMajor() => minorUnits / _factor(currency);

  bool get isZero => minorUnits == 0;
  bool get isNegative => minorUnits < 0;

  Money operator +(Money other) {
    _checkSameCurrency(other);
    return Money(minorUnits + other.minorUnits, currency);
  }

  Money operator -(Money other) {
    _checkSameCurrency(other);
    return Money(minorUnits - other.minorUnits, currency);
  }

  /// Exact multiplication by a whole count, e.g. unit price × quantity.
  Money operator *(int count) => Money(minorUnits * count, currency);

  /// Multiplies by a non-integer [factor] (a fee rate, a margin) and rounds
  /// the result once to a whole minor unit.
  Money scale(double factor) =>
      Money(_roundDouble(minorUnits * factor), currency);

  /// Converts into [target] at [rate] (`amountIn(currency) * rate ==
  /// amountIn(target)`, the same convention as `functions/lib/fx.js`'s
  /// `getRate`), rounding once to [target]'s minor unit.
  Money convertTo(String target, double rate) {
    if (target == currency) return this;
    return Money.fromMajor(toMajor() * rate, target);
  }

  @override
  int compareTo(Money other) {
    _checkSameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minorUnits == minorUnits &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  @override
  String toString() =>
      '${toMajor().toStringAsFixed(Currencies.of(currency).decimalDigits)} '
      '$currency';

  void _checkSameCurrency(Money other) {
    if (other.currency != currency) {
      throw ArgumentError(
          'Cannot combine $currency with ${other.currency} — convert first');
    }
  }

  static int _factor(String currency) {
    var factor = 1;
    for (var i = 0; i < Currencies.of(currency).decimalDigits; i++) {
      factor *= 10;
    }
    return factor;
  }

  static int _roundToMinor(double amount, int factor) =>
      _roundDouble(amount * factor);

  /// `1.005 * 100` is `100.49999999999999` in binary floating point, which a
  /// plain `.round()` would take down to 100. Snapping to 6 decimal places
  /// first discards that representation error before rounding — far below
  /// any real minor-unit precision, far above double's noise.
  static int _roundDouble(double value) =>
      double.parse(value.toStringAsFixed(6)).round();
}
