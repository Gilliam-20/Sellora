import 'package:get/get.dart';
import '../../models/product_model.dart';
import '../../mock/mock_seed_data.dart';
import '../product_repository.dart';

class MockProductRepository extends GetxService implements ProductRepository {
  final List<ProductModel> _catalog = MockSeedData.catalog();
  final List<ProductModel> _listings = [];

  @override
  Future<List<ProductModel>> browseCatalog({String? keyword, String? category}) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _catalog.where((p) {
      final matchesKeyword = keyword == null || keyword.isEmpty || p.title.toLowerCase().contains(keyword.toLowerCase());
      final matchesCategory = category == null || category == 'All' || p.category == category;
      return matchesKeyword && matchesCategory;
    }).toList();
  }

  @override
  Future<List<ProductModel>> sellerListings(String sellerId) async {
    await Future.delayed(const Duration(milliseconds: 250));
    if (_listings.where((p) => p.sellerId == sellerId).isEmpty) {
      // Seed a starter storefront so the seller dashboard isn't empty on first run.
      _listings.addAll(_catalog.take(3).map((p) => p.copyWith(sellerId: sellerId, isListed: true)));
    }
    return _listings.where((p) => p.sellerId == sellerId).toList();
  }

  @override
  Future<List<ProductModel>> storefrontFeed({String? keyword, String? category}) async {
    await Future.delayed(const Duration(milliseconds: 300));
    // Ensure at least one seller has listed something for the storefront demo.
    if (_listings.isEmpty) {
      _listings.addAll(_catalog.map((p) => p.copyWith(sellerId: 'mock-seller', isListed: true)));
    }
    return _listings.where((p) {
      final matchesKeyword = keyword == null || keyword.isEmpty || p.title.toLowerCase().contains(keyword.toLowerCase());
      final matchesCategory = category == null || category == 'All' || p.category == category;
      return p.isListed && matchesKeyword && matchesCategory;
    }).toList();
  }

  @override
  Future<ProductModel> productDetail(String productId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return [..._catalog, ..._listings].firstWhere((p) => p.id == productId);
  }

  @override
  Future<void> listProduct({required ProductModel catalogProduct, required String sellerId, required double sellPrice}) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _listings.add(catalogProduct.copyWith(sellerId: sellerId, isListed: true, sellPrice: sellPrice));
  }

  @override
  Future<void> updateListing(ProductModel product) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final index = _listings.indexWhere((p) => p.id == product.id);
    if (index != -1) _listings[index] = product;
  }

  @override
  Future<void> unlistProduct(String productId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final index = _listings.indexWhere((p) => p.id == productId);
    if (index != -1) _listings[index] = _listings[index].copyWith(isListed: false);
  }
}
