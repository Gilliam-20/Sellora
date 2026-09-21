import 'package:get/get.dart';
import '../../models/cj_category.dart';
import '../../models/freight_estimate.dart';
import '../../models/product_model.dart';
import '../../mock/mock_seed_data.dart';
import '../product_repository.dart';
import '../store_repository.dart';

class MockProductRepository extends GetxService implements ProductRepository {
  MockProductRepository() {
    // The two known mock stores (see MockSeedData.stores()) get distinct,
    // deliberate starter catalogs — otherwise both would lazily seed the
    // *same* first three catalog items on first access below, and the
    // store tenant boundary would have nothing visible to demonstrate.
    _listings.addAll([
      ..._catalog.take(3).map((p) => p.copyWith(
          sellerId: 'mock-seller', storeId: 'store-aminas', isListed: true)),
      ..._catalog.skip(3).take(3).map((p) => p.copyWith(
          sellerId: 'mock-seller-2',
          storeId: 'store-jengo',
          isListed: true)),
    ]);
  }

  final List<ProductModel> _catalog = MockSeedData.catalog();
  final List<ProductModel> _listings = [];

  @override
  Future<List<ProductModel>> browseCatalog(
      {String? keyword, String? category}) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _catalog.where((p) {
      final matchesKeyword = keyword == null ||
          keyword.isEmpty ||
          p.title.toLowerCase().contains(keyword.toLowerCase());
      final matchesCategory =
          category == null || category == 'All' || p.category == category;
      return matchesKeyword && matchesCategory;
    }).toList();
  }

  @override
  Future<List<CjCategory>> categories() async {
    await Future.delayed(const Duration(milliseconds: 150));
    // Mock filtering matches `p.category == category` directly (see
    // browseCatalog below), so the "id" here has to be the same display
    // name string the seed data actually carries.
    final names = _catalog.map((p) => p.category).toSet().toList()..sort();
    return names.map((n) => CjCategory(id: n, name: n)).toList();
  }

  @override
  Future<FreightEstimate> estimateShipping({
    required String vid,
    int quantity = 1,
    String endCountryCode = 'KE',
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    // Deterministic per-vid fake (~$2.50-$12.00) so a demo quotes the same
    // number for the same SKU every time, rather than a random one.
    final base = 2.5 + (vid.hashCode.abs() % 950) / 100;
    return FreightEstimate(
      cost: double.parse((base * quantity).toStringAsFixed(2)),
      logisticName: 'Standard Line (demo estimate)',
    );
  }

  @override
  Future<List<FreightOption>> shippingOptions({
    required List<Map<String, dynamic>> products,
    String endCountryCode = 'KE',
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    // Deterministic per-cart fake so a demo quotes the same three methods
    // for the same cart every time, rather than random ones.
    final key = products.map((p) => '${p['vid']}x${p['quantity']}').join('|');
    final base = 2.5 + (key.hashCode.abs() % 950) / 100;
    return [
      FreightOption(
        logisticName: 'CJPacket Ordinary (demo estimate)',
        cost: double.parse(base.toStringAsFixed(2)),
        estimatedDelivery: '12-20 days',
      ),
      FreightOption(
        logisticName: 'CJPacket Expedited (demo estimate)',
        cost: double.parse((base * 1.8).toStringAsFixed(2)),
        estimatedDelivery: '7-12 days',
      ),
      FreightOption(
        logisticName: 'DHL Express (demo estimate)',
        cost: double.parse((base * 3.2).toStringAsFixed(2)),
        estimatedDelivery: '3-6 days',
      ),
    ];
  }

  @override
  Future<List<ProductModel>> sellerListings(String sellerId) async {
    await Future.delayed(const Duration(milliseconds: 250));
    if (_listings.where((p) => p.sellerId == sellerId).isEmpty) {
      // Seed a starter storefront for any other seller (e.g. the seller
      // onboarding demo) so their dashboard isn't empty on first run. The
      // two known mock stores above are pre-seeded in the constructor
      // instead, with distinct products rather than this generic set.
      final stores = await Get.find<StoreRepository>().storesForSeller(sellerId);
      final storeId = stores.isEmpty ? null : stores.first.id;
      _listings.addAll(_catalog.take(3).map((p) => p.copyWith(
          sellerId: sellerId, storeId: storeId, isListed: true)));
    }
    return _listings.where((p) => p.sellerId == sellerId).toList();
  }

  @override
  Future<List<ProductModel>> storeProducts(
    String storeId, {
    String? keyword,
    String? category,
  }) async {
    // Demo mode mirrors the target store-owned path by resolving the store
    // first, then returning only that store owner's seed listings.
    final store = await Get.find<StoreRepository>().storeById(storeId);
    if (store == null) return const [];
    final listings = await sellerListings(store.sellerId);
    return listings.where((product) {
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
    await Future.delayed(const Duration(milliseconds: 300));
    // Ensure at least one seller has listed something for the storefront demo.
    if (_listings.isEmpty) {
      _listings.addAll(_catalog
          .map((p) => p.copyWith(sellerId: 'mock-seller', isListed: true)));
    }
    return _listings.where((p) {
      final matchesKeyword = keyword == null ||
          keyword.isEmpty ||
          p.title.toLowerCase().contains(keyword.toLowerCase());
      final matchesCategory =
          category == null || category == 'All' || p.category == category;
      return p.isListed && matchesKeyword && matchesCategory;
    }).toList();
  }

  @override
  Future<ProductModel> productDetail(String productId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return [..._catalog, ..._listings].firstWhere((p) => p.id == productId);
  }

  @override
  Future<void> listProduct(
      {required ProductModel catalogProduct,
      required String storeId,
      required String sellerId,
      required double sellPrice,
      bool isListed = true}) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _listings.add(catalogProduct.copyWith(
        sellerId: sellerId,
        storeId: storeId,
        isListed: isListed,
        sellPrice: sellPrice));
  }

  @override
  Future<void> updateListing(ProductModel product) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final index = _listings.indexWhere((p) => p.id == product.id);
    if (index != -1) _listings[index] = product;
  }

  @override
  Future<void> unlistProduct(String storeId, String productId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final index = _listings.indexWhere((p) => p.id == productId);
    if (index != -1) {
      _listings[index] = _listings[index].copyWith(isListed: false);
    }
  }
}
