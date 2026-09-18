/// A product in the shared Sellora catalog, sourced from CJ
/// Dropshipping. `cjProductId`/`cjSku` map back to CJ's own identifiers
/// so fulfillment can place the order directly with them.
///
/// `sellPrice` is what the *seller* has chosen to charge (their base
/// cost from CJ plus their own margin); `costPrice` is CJ's cost so a
/// seller's dashboard can show real margin, not just revenue.
class ProductModel {
  ProductModel({
    required this.id,
    required this.cjProductId,
    required this.title,
    required this.imageUrl,
    this.images = const [],
    required this.costPrice,
    required this.sellPrice,
    this.compareAtPrice,
    this.currency = 'USD',
    required this.category,
    this.description = '',
    this.variants = const [],
    this.sellerId,
    this.storeId,
    this.isListed = false,
    this.soldCount = 0,
    this.rating = 0,
    this.stock = 0,
    this.discountPercent,
  });

  final String id;
  final String cjProductId;
  final String title;
  final String imageUrl;
  final List<String> images;

  final double costPrice; // what CJ charges
  final double sellPrice; // what the seller charges the buyer
  final double? compareAtPrice;
  final String currency;

  final String category;
  final String description;
  final List<ProductVariant> variants;

  /// Null while sitting in the shared CJ catalog; set once a seller
  /// lists it in their own store.
  final String? sellerId;

  /// Which store's `stores/{storeId}/products` subcollection this listing
  /// lives in. Null while sitting in the shared CJ catalog, same as
  /// [sellerId] — set together by [ProductRepository.listProduct].
  final String? storeId;
  final bool isListed;

  final int soldCount;
  final double rating;
  final int stock;
  final int? discountPercent;

  double get margin => sellPrice - costPrice;
  double get marginPercent => costPrice == 0 ? 0 : (margin / costPrice) * 100;

  ProductModel copyWith({
    double? sellPrice,
    String? sellerId,
    String? storeId,
    bool? isListed,
    int? stock,
    List<ProductVariant>? variants,
  }) {
    return ProductModel(
      id: id,
      cjProductId: cjProductId,
      title: title,
      imageUrl: imageUrl,
      images: images,
      costPrice: costPrice,
      sellPrice: sellPrice ?? this.sellPrice,
      compareAtPrice: compareAtPrice,
      currency: currency,
      category: category,
      description: description,
      variants: variants ?? this.variants,
      sellerId: sellerId ?? this.sellerId,
      storeId: storeId ?? this.storeId,
      isListed: isListed ?? this.isListed,
      soldCount: soldCount,
      rating: rating,
      stock: stock ?? this.stock,
      discountPercent: discountPercent,
    );
  }

  /// Variants a buyer can actually pick, after the seller has disabled any
  /// via [ManageVariantsController]. Falls back to the full list if the
  /// seller has disabled every variant, so a listing can never end up with
  /// zero pickable SKUs.
  List<ProductVariant> get visibleVariants {
    final enabled = variants.where((v) => v.enabled).toList();
    return enabled.isNotEmpty ? enabled : variants;
  }

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      id: map['id'] as String,
      cjProductId: map['cjProductId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      imageUrl: map['imageUrl'] as String? ?? '',
      images: List<String>.from(map['images'] as List? ?? []),
      costPrice: (map['costPrice'] as num?)?.toDouble() ?? 0,
      sellPrice: (map['sellPrice'] as num?)?.toDouble() ?? 0,
      compareAtPrice: (map['compareAtPrice'] as num?)?.toDouble(),
      currency: map['currency'] as String? ?? 'USD',
      category: map['category'] as String? ?? 'General',
      description: map['description'] as String? ?? '',
      variants: (map['variants'] as List? ?? [])
          .map((v) => ProductVariant.fromMap(Map<String, dynamic>.from(v as Map)))
          .toList(),
      sellerId: map['sellerId'] as String?,
      storeId: map['storeId'] as String?,
      isListed: map['isListed'] as bool? ?? false,
      soldCount: map['soldCount'] as int? ?? 0,
      rating: (map['rating'] as num?)?.toDouble() ?? 0,
      stock: map['stock'] as int? ?? 0,
      discountPercent: map['discountPercent'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cjProductId': cjProductId,
      'title': title,
      'imageUrl': imageUrl,
      'images': images,
      'costPrice': costPrice,
      'sellPrice': sellPrice,
      'compareAtPrice': compareAtPrice,
      'currency': currency,
      'category': category,
      'description': description,
      'variants': variants.map((v) => v.toMap()).toList(),
      'sellerId': sellerId,
      'storeId': storeId,
      'isListed': isListed,
      'soldCount': soldCount,
      'rating': rating,
      'stock': stock,
      'discountPercent': discountPercent,
    };
  }
}

/// One purchasable CJ SKU. `vid` is CJ's own per-variant id — the exact
/// value `createOrder`'s `{pid, vid, quantity}` line-item shape requires
/// (functions/lib/orders.js), so it has to survive from catalog import all
/// the way to checkout, not just describe the option for display.
///
/// `price`/`costPrice` are CJ's own per-SKU retail/supplier price, kept for
/// reference — they do NOT feed [ProductModel.sellPrice], which stays the
/// seller's single chosen price for the whole listing.
class ProductVariant {
  ProductVariant({
    required this.vid,
    this.sku = '',
    this.attributes = const {},
    this.price = 0,
    this.costPrice = 0,
    this.image,
    this.enabled = true,
  });

  final String vid;
  final String sku;
  final Map<String, String> attributes; // e.g. {"Color": "Black", "Size": "M"}
  final double price; // CJ's retailPriceUsd for this SKU
  final double costPrice; // CJ's supplierPriceUsd for this SKU
  final String? image;

  /// Whether a buyer can pick this SKU. Seller-controlled, defaults to true
  /// on import — see [ManageVariantsController]. Purely a visibility switch;
  /// disabling a variant never deletes it, so it can be turned back on.
  final bool enabled;

  /// Human-readable label for display/receipts, e.g. "Black / M".
  String get label => attributes.isNotEmpty ? attributes.values.join(' / ') : sku;

  ProductVariant copyWith({String? sku, bool? enabled}) {
    return ProductVariant(
      vid: vid,
      sku: sku ?? this.sku,
      attributes: attributes,
      price: price,
      costPrice: costPrice,
      image: image,
      enabled: enabled ?? this.enabled,
    );
  }

  factory ProductVariant.fromMap(Map<String, dynamic> map) {
    return ProductVariant(
      vid: map['vid'] as String? ?? '',
      sku: map['sku'] as String? ?? '',
      attributes: Map<String, String>.from(map['attributes'] as Map? ?? {}),
      price: (map['price'] as num?)?.toDouble() ?? 0,
      costPrice: (map['costPrice'] as num?)?.toDouble() ?? 0,
      image: map['image'] as String?,
      enabled: map['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'vid': vid,
      'sku': sku,
      'attributes': attributes,
      'price': price,
      'costPrice': costPrice,
      'image': image,
      'enabled': enabled,
    };
  }
}
