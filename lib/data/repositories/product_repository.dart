import '../models/cj_category.dart';
import '../models/freight_estimate.dart';
import '../models/product_model.dart';

/// Why the database refused to publish a listing.
enum ListingRejection {
  /// The plan's `listing_limit` is already used up.
  listingLimit,

  /// The seller isn't approved, is suspended, or their subscription has
  /// lapsed. Drafts are still allowed.
  notInGoodStanding,
}

/// Thrown by [ProductRepository.listProduct]/[ProductRepository.updateListing]
/// when the server refuses to publish, so controllers can explain it
/// without importing supabase_flutter.
class ListingRejected implements Exception {
  const ListingRejected(this.reason);
  final ListingRejection reason;

  @override
  String toString() => 'ListingRejected($reason)';
}

/// Storefront pages hold this many products; the next page is fetched with
/// `offset`.
const storefrontPageSize = 60;

abstract class ProductRepository {
  /// The full CJ Dropshipping-sourced catalog available to list from.
  /// [category] is a CJ category id (see [categories]), not a display name.
  Future<List<ProductModel>> browseCatalog({String? keyword, String? category});

  /// Top-level categories for the catalog browse screen's filter chip row.
  Future<List<CjCategory>> categories();

  /// Cheapest freight estimate for one SKU shipping to [endCountryCode]
  /// (Kenya by default). Feeds the seller import screen's landed-cost
  /// pricing card only — buyer checkout prices real freight server-side.
  Future<FreightEstimate> estimateShipping({
    required String vid,
    int quantity = 1,
    String endCountryCode = 'KE',
  });

  /// Every CJ shipping method available for a whole cart (`{vid, quantity}`
  /// per line) going to [endCountryCode] — lets the buyer choose a shipment
  /// type at checkout. The chosen [FreightOption.logisticName] is what
  /// `createOrder` re-validates and prices server-side, never the client's
  /// own [FreightOption.cost].
  Future<List<FreightOption>> shippingOptions({
    required List<Map<String, dynamic>> products,
    String endCountryCode = 'KE',
  });

  /// Products a specific seller has listed in their own store.
  Future<List<ProductModel>> sellerListings(String sellerId);

  /// Public, tenant-scoped products for one storefront, newest first, one
  /// page of at most [limit] from [offset]. New features must use this
  /// instead of querying a platform-wide listing feed. Buyer-facing:
  /// carries no cost prices.
  Future<List<ProductModel>> storeProducts(
    String storeId, {
    String? keyword,
    String? category,
    int offset = 0,
    int limit = storefrontPageSize,
  });

  /// All active listings across all sellers, paged like [storeProducts] —
  /// the retired shared-marketplace feed.
  Future<List<ProductModel>> storefrontFeed({
    String? keyword,
    String? category,
    int offset = 0,
    int limit = storefrontPageSize,
  });

  /// CJ's full detail for a catalog product: every variant with its `vid`
  /// and supplier cost, for the seller import screen.
  Future<ProductModel> productDetail(String productId);

  /// A seller lists a catalog product in their own store
  /// (`stores/{storeId}/products`) at their own price. [isListed] false
  /// imports it as a draft — the same unpublished state [unlistProduct]
  /// leaves an existing listing in, so it shows up in My listings but not
  /// on the storefront. Publishing can throw [ListingRejected].
  Future<void> listProduct(
      {required ProductModel catalogProduct,
      required String storeId,
      required String sellerId,
      required double sellPrice,
      bool isListed = true});

  /// [product.storeId] locates which store's subcollection to update —
  /// always set by [listProduct], since a listing can't exist without one.
  /// Publishing can throw [ListingRejected].
  Future<void> updateListing(ProductModel product);

  Future<void> unlistProduct(String storeId, String productId);
}
