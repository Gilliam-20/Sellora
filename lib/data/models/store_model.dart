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
    this.currencyCode = 'KES',
    this.createdAt,
  });

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

  final String currencyCode;
  final DateTime? createdAt;

  StoreModel copyWith({
    String? name,
    String? tagline,
    String? logoUrl,
    String? bannerUrl,
    String? primaryColorHex,
    String? currencyCode,
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
      currencyCode: currencyCode ?? this.currencyCode,
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
      currencyCode: map['currencyCode'] as String? ?? 'KES',
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
      'currencyCode': currencyCode,
      'createdAt': createdAt?.toIso8601String(),
    };
  }
}
