/// The currencies Sellora prices, displays and settles in (build spec §36):
/// KES, USD, GBP, EUR. Mirrors the currencies `functions/lib/regions.js`
/// resolves a shipping country to and `functions/lib/fx.js` caches rates
/// for — add a currency in all three places, not just here.
class CurrencyInfo {
  const CurrencyInfo({
    required this.code,
    required this.symbol,
    required this.name,
    this.decimalDigits = 2,
  });

  /// ISO 4217 code, e.g. `'KES'`.
  final String code;

  /// Display prefix, including any trailing space (`'KSh '` vs `'$'`).
  final String symbol;
  final String name;

  /// Minor-unit exponent — how many digits after the decimal point an
  /// amount carries (100 cents per dollar => 2). [Money] stores amounts as
  /// integers of this minor unit.
  final int decimalDigits;
}

class Currencies {
  Currencies._();

  static const kes =
      CurrencyInfo(code: 'KES', symbol: 'KSh ', name: 'Kenyan shilling');
  static const usd = CurrencyInfo(code: 'USD', symbol: r'$', name: 'US dollar');
  static const gbp =
      CurrencyInfo(code: 'GBP', symbol: '£', name: 'British pound');
  static const eur = CurrencyInfo(code: 'EUR', symbol: '€', name: 'Euro');

  /// Kenya first, matching the product's Kenya-first positioning.
  static const all = [kes, usd, gbp, eur];

  static List<String> get codes => all.map((c) => c.code).toList();

  static bool isSupported(String code) => all.any((c) => c.code == code);

  /// The registered [CurrencyInfo] for [code], or a generic 2-decimal
  /// entry using the code itself as its symbol — an unknown currency still
  /// formats legibly rather than throwing mid-render.
  static CurrencyInfo of(String code) {
    for (final c in all) {
      if (c.code == code) return c;
    }
    return CurrencyInfo(code: code, symbol: '$code ', name: code);
  }
}
