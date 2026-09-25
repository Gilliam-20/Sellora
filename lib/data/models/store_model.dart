/// A seller's storefront/tenant. Buyers register as a customer of one
/// `StoreModel` (see `stores/{id}/customers/{uid}` in Firestore) rather
/// than as a global Sellora account — `sellerId` ties the store back to
/// the [UserModel] (role == seller) that owns and manages it.
class StoreModel {
  StoreModel({
    required this.id,
    required this.slug,
    required this.sellerId,
    required this.name,
    this.tagline,
    this.logoUrl,
    this.bannerUrl,
    this.primaryColorHex,
    this.category,
    this.countryCode,
    this.currencyCode = 'KES',
    this.shippingZones = allShippingZoneIds,
    this.createdAt,
  });

  /// Every zone id `lib/core/i18n/countries.dart`'s `ShippingZone` defines,
  /// duplicated as plain strings so this model stays import-free. A store
  /// document written before shipping zones existed ships everywhere, which
  /// is what checkout offered before this field did.
  static const allShippingZoneIds = ['kenya', 'us', 'uk', 'eu'];

  final String id;

  /// URL-safe handle for the store's public storefront, e.g.
  /// `sellora.app/s/{slug}`. Must be unique platform-wide.
  final String slug;

  /// The owning seller's [UserModel.uid].
  final String sellerId;

  final String name;

  // ---- Branding ---------------------------------------------------------
  final String? tagline;
  final String? logoUrl;
  final String? bannerUrl;

  /// Hex string (e.g. `'#16213E'`) rather than a `Color`, so this model
  /// stays free of Flutter imports like every other model in `data/models`.
  final String? primaryColorHex;

  // ---- Onboarding profile -----------------------------------------------
  /// One of [StoreCategories.all]'s ids. Null until the seller completes
  /// onboarding's store-setup step.
  final String? category;

  /// ISO 3166-1 alpha-2 code of the country the seller operates from — not
  /// where they ship to (that's [shippingZones]). Null until store setup.
  final String? countryCode;

  final String currencyCode;

  /// Ids of the `ShippingZone`s (server pricing regions) this store ships
  /// to — checkout only offers countries in these zones. Enforced
  /// client-side only for now: the adopted single-vendor `createOrder` has
  /// no store concept to check it against (see WORKLOG.md, PHASE 11).
  final List<String> shippingZones;
  final DateTime? createdAt;

  /// Whether the seller has been through onboarding's store-setup step.
  bool get isSetUp => category != null && countryCode != null;

  StoreModel copyWith({
    String? name,
    String? tagline,
    String? logoUrl,
    String? bannerUrl,
    String? primaryColorHex,
    String? category,
    String? countryCode,
    String? currencyCode,
    List<String>? shippingZones,
  }) {
    return StoreModel(
      id: id,
      slug: slug,
      sellerId: sellerId,
      name: name ?? this.name,
      tagline: tagline ?? this.tagline,
      logoUrl: logoUrl ?? this.logoUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      primaryColorHex: primaryColorHex ?? this.primaryColorHex,
      category: category ?? this.category,
      countryCode: countryCode ?? this.countryCode,
      currencyCode: currencyCode ?? this.currencyCode,
      shippingZones: shippingZones ?? this.shippingZones,
      createdAt: createdAt,
    );
  }

  factory StoreModel.fromMap(Map<String, dynamic> map) {
    return StoreModel(
      id: map['id'] as String,
      slug: map['slug'] as String? ?? '',
      sellerId: map['sellerId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      tagline: map['tagline'] as String?,
      logoUrl: map['logoUrl'] as String?,
      bannerUrl: map['bannerUrl'] as String?,
      primaryColorHex: map['primaryColorHex'] as String?,
      category: map['category'] as String?,
      countryCode: map['countryCode'] as String?,
      currencyCode: map['currencyCode'] as String? ?? 'KES',
      shippingZones:
          (map['shippingZones'] as List?)?.cast<String>() ?? allShippingZoneIds,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'slug': slug,
      'sellerId': sellerId,
      'name': name,
      'tagline': tagline,
      'logoUrl': logoUrl,
      'bannerUrl': bannerUrl,
      'primaryColorHex': primaryColorHex,
      'category': category,
      'countryCode': countryCode,
      'currencyCode': currencyCode,
      'shippingZones': shippingZones,
      'createdAt': createdAt?.toIso8601String(),
    };
  }
}

/// The store categories onboarding offers. Keys are persisted on
/// [StoreModel.category]; values are display labels.
class StoreCategories {
  StoreCategories._();

  static const all = <String, String>{
    'fashion': 'Fashion & apparel',
    'electronics': 'Electronics & gadgets',
    'home': 'Home & living',
    'beauty': 'Beauty & personal care',
    'kids': 'Kids & baby',
    'sports': 'Sports & outdoors',
    'general': 'General store',
  };
}
