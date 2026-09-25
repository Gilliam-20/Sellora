import 'package:get/get.dart';
import '../models/cj_category.dart';
import '../models/freight_estimate.dart';
import '../models/product_model.dart';
import '../services/cj_dropshipping_service.dart';
import '../services/supabase_service.dart';
import 'product_repository.dart';

/// Production implementation: catalog browsing goes through
/// [CjDropshippingService] (backend -> CJ Dropshipping API); listings and
/// storefront reads/writes go through the `products` table.
class SupabaseProductRepository extends GetxService
    implements ProductRepository {
  final SupabaseService _db = Get.find<SupabaseService>();
  final CjDropshippingService _cj = Get.find<CjDropshippingService>();

  @override
  Future<List<ProductModel>> browseCatalog(
      {String? keyword, String? category}) {
    return _cj.searchProducts(keyword: keyword, categoryId: category);
  }

  @override
  Future<List<CjCategory>> categories() => _cj.getCategories();

  @override
  Future<FreightEstimate> estimateShipping({
    required String vid,
    int quantity = 1,
    String endCountryCode = 'KE',
  }) {
    return _cj.calculateFreight(
      endCountryCode: endCountryCode,
      products: [
        {'vid': vid, 'quantity': quantity}
      ],
    );
  }

  @override
  Future<List<FreightOption>> shippingOptions({
    required List<Map<String, dynamic>> products,
    String endCountryCode = 'KE',
  }) {
    return _cj.getShippingOptions(
      endCountryCode: endCountryCode,
      products: products,
    );
  }

  @override
  Future<List<ProductModel>> sellerListings(String sellerId) async {
    final rows = await _db.products.select().eq('seller_id', sellerId);
    return _models(rows);
  }

  @override
  Future<List<ProductModel>> storeProducts(
    String storeId, {
    String? keyword,
    String? category,
  }) async {
    var query =
        _db.products.select().eq('store_id', storeId).eq('is_listed', true);
    if (category != null && category != 'All') {
      query = query.eq('category', category);
    }
    if (keyword != null && keyword.isNotEmpty) {
      query = query.ilike('title', '%${_escapeLike(keyword)}%');
    }
    return _models(await query);
  }

  @override
  Future<List<ProductModel>> storefrontFeed(
      {String? keyword, String? category}) async {
    var query = _db.products.select().eq('is_listed', true);
    if (category != null && category != 'All') {
      query = query.eq('category', category);
    }
    if (keyword != null && keyword.isNotEmpty) {
      query = query.ilike('title', '%${_escapeLike(keyword)}%');
    }
    return _models(await query);
  }

  @override
  Future<ProductModel> productDetail(String productId) async {
    // A listed product's id is the CJ product id, unique only within its
    // store — so this takes the first store's listing, then falls back to
    // CJ's own detail for an unlisted catalog product.
    final row =
        await _db.products.select().eq('id', productId).limit(1).maybeSingle();
    if (row != null) return ProductModel.fromMap(fromRow(row));
    return _cj.productDetail(productId);
  }

  @override
  Future<void> listProduct(
      {required ProductModel catalogProduct,
      required String storeId,
      required String sellerId,
      required double sellPrice,
      bool isListed = true}) async {
    final listed = catalogProduct.copyWith(
        sellerId: sellerId,
        storeId: storeId,
        isListed: isListed,
        sellPrice: sellPrice);
    // Keyed (store_id, id), so re-listing the same catalog product in the
    // same store overwrites it, as the Firestore doc id did.
    await _db.products.upsert(toRow(listed.toMap()), onConflict: 'store_id,id');
  }

  @override
  Future<void> updateListing(ProductModel product) async {
    final storeId = product.storeId;
    if (storeId == null) {
      throw StateError(
          'Cannot update a listing with no storeId: ${product.id}');
    }
    await _db.products
        .update(toRow(product.toMap(), omit: const {'id', 'storeId'}))
        .eq('store_id', storeId)
        .eq('id', product.id);
  }

  @override
  Future<void> unlistProduct(String storeId, String productId) async {
    await _db.products
        .update({'is_listed': false})
        .eq('store_id', storeId)
        .eq('id', productId);
  }

  List<ProductModel> _models(List<Map<String, dynamic>> rows) =>
      rows.map((r) => ProductModel.fromMap(fromRow(r))).toList();

  /// `%` and `_` in a buyer's search are literal text, not wildcards.
  static String _escapeLike(String input) =>
      input.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}');
}
