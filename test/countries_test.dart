import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sellora/core/i18n/countries.dart';
import 'package:sellora/core/i18n/currencies.dart';
import 'package:sellora/data/models/store_model.dart';

void main() {
  group('Countries mirrors supabase/functions/_shared/regions.js', () {
    // The server derives an order's currency from the shipping country via
    // regions.js — if the app's country list disagrees, checkout would show
    // one currency and the server would charge in another.
    final source = File('supabase/functions/_shared/regions.js').readAsStringSync();

    test('every EU member code is configured in the eu zone', () {
      final array = RegExp(r'EU_MEMBER_COUNTRY_CODES = \[([^\]]*)\]')
          .firstMatch(source)!
          .group(1)!;
      final serverEu = RegExp(r'"([A-Z]{2})"')
          .allMatches(array)
          .map((m) => m.group(1)!)
          .toSet();
      final appEu = ShippingZone.eu.countries.map((c) => c.code).toSet();
      expect(appEu, serverEu);
    });

    test('named regions match zone ids and currencies', () {
      final entries = RegExp(
              r'([A-Z]{2}): Object\.freeze\(\{ region: "(\w+)", currency: "([A-Z]{3})" \}\)')
          .allMatches(source);
      expect(entries, isNotEmpty);
      for (final m in entries) {
        final country = Countries.byCode(m.group(1)!);
        expect(country, isNotNull, reason: '${m.group(1)} missing');
        expect(country!.zone.id, m.group(2));
        expect(country.currency, m.group(3));
      }
    });

    test('unknown countries fall back to US/USD like resolveRegion', () {
      expect(source, contains('region: "us", currency: "USD"'));
      expect(Countries.resolve('ZZ').zone, ShippingZone.us);
      expect(Countries.resolve(' ke ').code, 'KE');
    });
  });

  test('every zone prices in a supported currency', () {
    for (final zone in ShippingZone.values) {
      expect(Currencies.isSupported(zone.currency), isTrue);
    }
  });

  test('StoreModel.allShippingZoneIds matches ShippingZone', () {
    expect(StoreModel.allShippingZoneIds,
        ShippingZone.values.map((z) => z.id).toList());
  });

  test('M-Pesa is only offered for Kenya', () {
    expect(Countries.kenya.paymentMethods, contains(PaymentMethodType.mpesa));
    for (final c in Countries.all.where((c) => c.code != 'KE')) {
      expect(c.paymentMethods, [PaymentMethodType.card], reason: c.code);
    }
  });

  test('forZones lists Kenya first, then alphabetically', () {
    final list = Countries.forZones([ShippingZone.eu, ShippingZone.kenya]);
    expect(list.first.code, 'KE');
    final rest = list.skip(1).map((c) => c.name).toList();
    expect(rest, [...rest]..sort());
    expect(list.any((c) => c.code == 'US'), isFalse);
  });

  test('StoreModel without shippingZones ships everywhere', () {
    final store = StoreModel.fromMap(
        {'id': 's', 'slug': 's', 'sellerId': 'u', 'name': 'S'});
    expect(store.shippingZones, StoreModel.allShippingZoneIds);
    final roundTripped =
        StoreModel.fromMap(store.copyWith(shippingZones: ['kenya']).toMap());
    expect(roundTripped.shippingZones, ['kenya']);
  });
}
