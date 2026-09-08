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
    bool? isListed,
    int? stock,
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
      variants: variants,
      sellerId: sellerId ?? this.sellerId,
      isListed: isListed ?? this.isListed,
      soldCount: soldCount,
      rating: rating,
      stock: stock ?? this.stock,
      discountPercent: discountPercent,
    );
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
      sellerId: map['sellerId'] as String?,
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
      'sellerId': sellerId,
      'isListed': isListed,
      'soldCount': soldCount,
      'rating': rating,
      'stock': stock,
      'discountPercent': discountPercent,
    };
  }
}

class ProductVariant {
  ProductVariant({required this.name, required this.options});
  final String name; // e.g. "Color"
  final List<String> options; // e.g. ["Black", "White"]
}
