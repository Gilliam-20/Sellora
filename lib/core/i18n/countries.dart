/// Country configuration — which countries Sellora ships to, which shipping
/// zone (pricing region) each belongs to, what currency that zone prices in,
/// and which payment methods a buyer there can actually use.
///
/// The country→zone→currency mapping mirrors `supabase/functions/_shared/regions.js`'s
/// `REGION_CONFIG` exactly (zone ids are its `region` keys), because the
/// server derives an order's currency from the shipping country itself and
/// never trusts the client's. `test/countries_test.dart` reads regions.js
/// and fails if the two drift apart.
library;

/// A seller-selectable group of destination countries — one per server
/// pricing region. A store ships to the union of its enabled zones (see
/// `StoreModel.shippingZones`).
enum ShippingZone {
  kenya('kenya', 'Kenya', 'KES'),
  us('us', 'United States', 'USD'),
  uk('uk', 'United Kingdom', 'GBP'),
  eu('eu', 'European Union', 'EUR');

  const ShippingZone(this.id, this.label, this.currency);

  /// Stable id persisted on `StoreModel.shippingZones` — matches
  /// regions.js's `region` value.
  final String id;
  final String label;

  /// The currency an order shipping into this zone is priced in.
  final String currency;

  static ShippingZone? byId(String id) {
    for (final zone in values) {
      if (zone.id == id) return zone;
    }
    return null;
  }

  /// Parses persisted zone ids, silently dropping unknown ones (a zone
  /// removed in a later release shouldn't crash an old store document).
  static List<ShippingZone> parseAll(Iterable<String> ids) =>
      ids.map(byId).whereType<ShippingZone>().toList();

  List<CountryConfig> get countries =>
      Countries.all.where((c) => c.zone == this).toList();
}

/// A way to pay at checkout. [intasendMethod] is the value
/// `supabase/functions/api/index.ts`'s `payOrderCard` expects for hosted-checkout
/// methods; M-Pesa has its own STK-push endpoint instead.
enum PaymentMethodType {
  mpesa('M-Pesa', 'IntaSend M-Pesa', null),
  card('Card', 'IntaSend Card', 'CARD-PAYMENT');

  const PaymentMethodType(this.label, this.orderLabel, this.intasendMethod);

  final String label;

  /// What's written to `OrderModel.paymentMethod`.
  final String orderLabel;
  final String? intasendMethod;
}

class CountryConfig {
  const CountryConfig(this.code, this.name, this.zone);

  /// ISO 3166-1 alpha-2.
  final String code;
  final String name;
  final ShippingZone zone;

  String get currency => zone.currency;

  /// M-Pesa STK push only reaches Kenyan (+254) numbers; card checkout is
  /// IntaSend's hosted page and works internationally.
  List<PaymentMethodType> get paymentMethods => code == 'KE'
      ? const [PaymentMethodType.mpesa, PaymentMethodType.card]
      : const [PaymentMethodType.card];
}

class Countries {
  Countries._();

  static const kenya = CountryConfig('KE', 'Kenya', ShippingZone.kenya);
  static const unitedStates =
      CountryConfig('US', 'United States', ShippingZone.us);

  /// Every configured destination. EU members are all mapped to the `eu`
  /// zone/EUR regardless of whether they circulate the euro — same as
  /// regions.js: this is a shipping/pricing region, not a currency union.
  static const all = [
    kenya,
    unitedStates,
    CountryConfig('GB', 'United Kingdom', ShippingZone.uk),
    CountryConfig('AT', 'Austria', ShippingZone.eu),
    CountryConfig('BE', 'Belgium', ShippingZone.eu),
    CountryConfig('BG', 'Bulgaria', ShippingZone.eu),
    CountryConfig('HR', 'Croatia', ShippingZone.eu),
    CountryConfig('CY', 'Cyprus', ShippingZone.eu),
    CountryConfig('CZ', 'Czechia', ShippingZone.eu),
    CountryConfig('DK', 'Denmark', ShippingZone.eu),
    CountryConfig('EE', 'Estonia', ShippingZone.eu),
    CountryConfig('FI', 'Finland', ShippingZone.eu),
    CountryConfig('FR', 'France', ShippingZone.eu),
    CountryConfig('DE', 'Germany', ShippingZone.eu),
    CountryConfig('GR', 'Greece', ShippingZone.eu),
    CountryConfig('HU', 'Hungary', ShippingZone.eu),
    CountryConfig('IE', 'Ireland', ShippingZone.eu),
    CountryConfig('IT', 'Italy', ShippingZone.eu),
    CountryConfig('LV', 'Latvia', ShippingZone.eu),
    CountryConfig('LT', 'Lithuania', ShippingZone.eu),
    CountryConfig('LU', 'Luxembourg', ShippingZone.eu),
    CountryConfig('MT', 'Malta', ShippingZone.eu),
    CountryConfig('NL', 'Netherlands', ShippingZone.eu),
    CountryConfig('PL', 'Poland', ShippingZone.eu),
    CountryConfig('PT', 'Portugal', ShippingZone.eu),
    CountryConfig('RO', 'Romania', ShippingZone.eu),
    CountryConfig('SK', 'Slovakia', ShippingZone.eu),
    CountryConfig('SI', 'Slovenia', ShippingZone.eu),
    CountryConfig('ES', 'Spain', ShippingZone.eu),
    CountryConfig('SE', 'Sweden', ShippingZone.eu),
  ];

  static CountryConfig? byCode(String code) {
    final normalized = code.trim().toUpperCase();
    for (final c in all) {
      if (c.code == normalized) return c;
    }
    return null;
  }

  /// Same fallback as regions.js's `resolveRegion`: an unrecognized country
  /// prices as the US/USD region.
  static CountryConfig resolve(String code) => byCode(code) ?? unitedStates;

  /// The countries a store with [zones] enabled can ship to — Kenya first
  /// (the product's home market), then alphabetical.
  static List<CountryConfig> forZones(Iterable<ShippingZone> zones) {
    final enabled = zones.toSet();
    final list = all.where((c) => enabled.contains(c.zone)).toList()
      ..sort((a, b) {
        if (a.code == 'KE') return -1;
        if (b.code == 'KE') return 1;
        return a.name.compareTo(b.name);
      });
    return list;
  }
}
