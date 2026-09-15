import '../models/product_model.dart';

abstract class ProductRepository {
  /// The full CJ Dropshipping-sourced catalog available to list from.
  Future<List<ProductModel>> browseCatalog({String? keyword, String? category});

  /// Products a specific seller has listed in their own store.
  Future<List<ProductModel>> sellerListings(String sellerId);

  /// Public, tenant-scoped products for one storefront. New features must
  /// use this instead of querying a platform-wide listing feed.
  Future<List<ProductModel>> storeProducts(
    String storeId, {
    String? keyword,
    String? category,
  });

  /// All active listings across all sellers, for the buyer storefront.
  Future<List<ProductModel>> storefrontFeed(
      {String? keyword, String? category});

  Future<ProductModel> productDetail(String productId);

  /// A seller lists a catalog product in their store at their own price.
  /// [isListed] false imports it as a draft — the same unpublished state
  /// [unlistProduct] leaves an existing listing in, so it shows up in My
  /// listings but not on the storefront.
  Future<void> listProduct(
      {required ProductModel catalogProduct,
      required String sellerId,
      required double sellPrice,
      bool isListed = true});

  Future<void> updateListing(ProductModel product);

  Future<void> unlistProduct(String productId);
}
