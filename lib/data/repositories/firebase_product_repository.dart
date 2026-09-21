import 'package:get/get.dart';
import '../models/cj_category.dart';
import '../models/freight_estimate.dart';
import '../models/product_model.dart';
import '../services/cj_dropshipping_service.dart';
import '../services/firestore_service.dart';
import 'product_repository.dart';

/// Production implementation: catalog browsing goes through
/// [CjDropshippingService] (Cloud Functions -> CJ Dropshipping API);
/// listings and storefront reads/writes go through Firestore.
class FirebaseProductRepository extends GetxService
    implements ProductRepository {
  final FirestoreService _fs = Get.find<FirestoreService>();
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
    final snap =
        await _fs.productsGroup.where('sellerId', isEqualTo: sellerId).get();
    return snap.docs.map((d) => ProductModel.fromMap(d.data())).toList();
  }

  @override
  Future<List<ProductModel>> storeProducts(
    String storeId, {
    String? keyword,
    String? category,
  }) async {
    final snap = await _fs.storeProducts(storeId).get();
    return snap.docs
        .map((d) => ProductModel.fromMap(d.data()))
        .where((product) {
      final matchesKeyword = keyword == null ||
          keyword.isEmpty ||
          product.title.toLowerCase().contains(keyword.toLowerCase());
      final matchesCategory =
          category == null || category == 'All' || product.category == category;
      return product.isListed && matchesKeyword && matchesCategory;
    }).toList();
  }

  @override
  Future<List<ProductModel>> storefrontFeed(
      {String? keyword, String? category}) async {
    var query = _fs.productsGroup.where('isListed', isEqualTo: true);
    if (category != null && category != 'All') {
      query = query.where('category', isEqualTo: category);
    }
    final snap = await query.get();
    var results = snap.docs.map((d) => ProductModel.fromMap(d.data())).toList();
    if (keyword != null && keyword.isNotEmpty) {
      results = results
          .where((p) => p.title.toLowerCase().contains(keyword.toLowerCase()))
          .toList();
    }
    return results;
  }

  @override
  Future<ProductModel> productDetail(String productId) async {
    // A listed product's own id, not the Firestore document id under
    // stores/{storeId}/products (see [listProduct]'s doc-id comment) — so
    // this has to search by field, not `.doc(productId).get()`.
    final snap = await _fs.productsGroup
        .where('id', isEqualTo: productId)
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) return ProductModel.fromMap(snap.docs.first.data());
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
    // Store-scoped now, so the old `${sellerId}_${catalogProduct.id}`
    // cross-seller collision-avoidance key is no longer needed.
    await _fs.storeProducts(storeId).doc(catalogProduct.id).set(listed.toMap());
  }

  @override
  Future<void> updateListing(ProductModel product) async {
    final storeId = product.storeId;
    if (storeId == null) {
      throw StateError('Cannot update a listing with no storeId: ${product.id}');
    }
    await _fs.storeProducts(storeId).doc(product.id).update(product.toMap());
  }

  @override
  Future<void> unlistProduct(String storeId, String productId) async {
    await _fs.storeProducts(storeId).doc(productId).update({'isListed': false});
  }
}
