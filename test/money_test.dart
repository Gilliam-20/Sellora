import 'package:flutter_test/flutter_test.dart';
import 'package:sellora/core/i18n/money.dart';
import 'package:sellora/core/utils/formatters.dart';
import 'package:sellora/data/models/fx_rates.dart';

void main() {
  group('Money', () {
    test('sums without floating-point drift', () {
      final total = Money.sum(
          List.generate(10, (_) => Money.fromMajor(0.1, 'USD')), 'USD');
      expect(total.minorUnits, 100);
      expect(total.toMajor(), 1.0);
    });

    test('rounds half away from zero despite binary representation', () {
      // 1.005 * 100 is 100.49999999999999 as a double.
      expect(Money.fromMajor(1.005, 'USD').minorUnits, 101);
      expect(Money.fromMajor(-1.005, 'USD').minorUnits, -101);
    });

    test('multiplies by quantity exactly and scales with one rounding', () {
      final unit = Money.fromMajor(19.99, 'KES');
      expect((unit * 3).minorUnits, 5997);
      expect(Money.fromMajor(10, 'USD').scale(0.02).minorUnits, 20);
    });

    test('refuses to combine different currencies', () {
      expect(() => Money.fromMajor(1, 'USD') + Money.fromMajor(1, 'KES'),
          throwsArgumentError);
    });

    test('converts and rounds to the target minor unit', () {
      final kes = Money.fromMajor(10, 'USD').convertTo('KES', 129.0);
      expect(kes, Money.fromMajor(1290, 'KES'));
    });
  });

  group('FxRates.rateBetween', () {
    const rates = FxRates(rates: {'KES': 129.0, 'EUR': 0.92, 'GBP': 0.79});

    test('reads base-to-quote rates directly', () {
      expect(rates.rateBetween('USD', 'KES'), 129.0);
      expect(rates.rateBetween('USD', 'USD'), 1);
    });

    test('inverts quote-to-base', () {
      expect(rates.rateBetween('KES', 'USD'), closeTo(1 / 129.0, 1e-12));
    });

    test('pivots through the base when neither side is the base', () {
      expect(rates.rateBetween('EUR', 'GBP'), closeTo(0.79 / 0.92, 1e-12));
    });

    test('returns null rather than guessing a missing rate', () {
      expect(rates.rateBetween('USD', 'JPY'), isNull);
    });
  });

  group('Formatters.currency', () {
    test('uses each supported currency\'s symbol', () {
      expect(Formatters.currency(1234.5, code: 'KES'), 'KSh 1,234.50');
      expect(Formatters.currency(1234.5, code: 'USD'), r'$1,234.50');
      expect(Formatters.currency(1234.5, code: 'GBP'), '£1,234.50');
      expect(Formatters.currency(1234.5, code: 'EUR'), '€1,234.50');
    });

    test('puts the sign before the symbol', () {
      expect(Formatters.currency(-5, code: 'USD'), r'-$5.00');
    });
  });
}
