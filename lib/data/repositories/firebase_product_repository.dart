import 'package:get/get.dart';
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
  Future<List<ProductModel>> sellerListings(String sellerId) async {
    final snap =
        await _fs.listings.where('sellerId', isEqualTo: sellerId).get();
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
    var query = _fs.listings.where('isListed', isEqualTo: true);
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
    final doc = await _fs.listings.doc(productId).get();
    if (doc.exists) return ProductModel.fromMap(doc.data()!);
    return _cj.productDetail(productId);
  }

  @override
  Future<void> listProduct(
      {required ProductModel catalogProduct,
      required String sellerId,
      required double sellPrice}) async {
    final listed = catalogProduct.copyWith(
        sellerId: sellerId, isListed: true, sellPrice: sellPrice);
    await _fs.listings
        .doc('${sellerId}_${catalogProduct.id}')
        .set(listed.toMap());
  }

  @override
  Future<void> updateListing(ProductModel product) async {
    await _fs.listings.doc(product.id).update(product.toMap());
  }

  @override
  Future<void> unlistProduct(String productId) async {
    await _fs.listings.doc(productId).update({'isListed': false});
  }
}
