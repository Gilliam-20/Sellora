import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sellora/data/models/cj_category.dart';
import 'package:sellora/data/models/freight_estimate.dart';
import 'package:sellora/data/models/product_model.dart';
import 'package:sellora/data/models/store_model.dart';
import 'package:sellora/data/models/user_model.dart';
import 'package:sellora/data/repositories/mock/mock_auth_repository.dart';
import 'package:sellora/data/repositories/mock/mock_subscription_repository.dart';
import 'package:sellora/data/repositories/product_repository.dart';
import 'package:sellora/data/repositories/store_repository.dart';

void main() {
  tearDown(Get.reset);

  test(
      'subscribeSeller activates the cached user and records a paid billing entry',
      () async {
    Get.put<ProductRepository>(_FakeProductRepository([]));
    final auth = MockAuthRepository(storeRepository: _FakeStoreRepository());
    final seller = await auth.signUpSeller(
      name: 'Amina',
      email: 'amina@example.com',
      password: 'password123',
      storeName: "Amina's Store",
      phone: '0712345678',
      hasAcceptedTerms: true,
    );
    final repo = MockSubscriptionRepository(authRepository: auth);

    final entry = await repo.subscribeSeller(
        sellerId: seller.uid, planId: 'growth');

    expect(entry.status, 'paid');
    expect(entry.planId, 'growth');
    expect(auth.cachedUser!.hasActiveSubscription, isTrue);
    expect(auth.cachedUser!.subscriptionPlanId, 'growth');
    expect(auth.cachedUser!.sellerStatus, SellerStatus.active);
  });

  test('fetchUsage reports the seller\'s listing count against the plan limit',
      () async {
    final auth = MockAuthRepository(storeRepository: _FakeStoreRepository());
    final seller = await auth.signUpSeller(
      name: 'Amina',
      email: 'amina@example.com',
      password: 'password123',
      storeName: "Amina's Store",
      phone: '0712345678',
      hasAcceptedTerms: true,
    );
    final products = _FakeProductRepository([
      ProductModel(
        id: 'p1',
        cjProductId: 'cj1',
        title: 'Item 1',
        imageUrl: '',
        costPrice: 1,
        sellPrice: 2,
        category: 'general',
        sellerId: seller.uid,
      ),
      ProductModel(
        id: 'p2',
        cjProductId: 'cj2',
        title: 'Item 2',
        imageUrl: '',
        costPrice: 1,
        sellPrice: 2,
        category: 'general',
        sellerId: seller.uid,
      ),
    ]);
    Get.put<ProductRepository>(products);
    final repo = MockSubscriptionRepository(authRepository: auth);
    await repo.subscribeSeller(sellerId: seller.uid, planId: 'starter');

    final usage = await repo.fetchUsage(seller.uid);

    expect(usage.listingCount, 2);
    expect(usage.listingLimit, 25); // starter plan's seeded limit
  });
}

class _FakeProductRepository implements ProductRepository {
  _FakeProductRepository(this._products);
  final List<ProductModel> _products;

  @override
  Future<List<ProductModel>> sellerListings(String sellerId) async =>
      _products.where((p) => p.sellerId == sellerId).toList();

  @override
  Future<List<ProductModel>> browseCatalog(
          {String? keyword, String? category}) =>
      throw UnimplementedError();

  @override
  Future<List<CjCategory>> categories() => throw UnimplementedError();

  @override
  Future<FreightEstimate> estimateShipping(
          {required String vid, int quantity = 1, String endCountryCode = 'KE'}) =>
      throw UnimplementedError();

  @override
  Future<List<ProductModel>> storeProducts(String storeId,
          {String? keyword, String? category}) =>
      throw UnimplementedError();

  @override
  Future<List<ProductModel>> storefrontFeed(
          {String? keyword, String? category}) =>
      throw UnimplementedError();

  @override
  Future<ProductModel> productDetail(String productId) =>
      throw UnimplementedError();

  @override
  Future<void> listProduct(
          {required ProductModel catalogProduct,
          required String storeId,
          required String sellerId,
          required double sellPrice,
          bool isListed = true}) =>
      throw UnimplementedError();

  @override
  Future<void> updateListing(ProductModel product) =>
      throw UnimplementedError();

  @override
  Future<void> unlistProduct(String storeId, String productId) =>
      throw UnimplementedError();
}

class _FakeStoreRepository implements StoreRepository {
  final List<StoreModel> _stores = [];

  @override
  Future<List<StoreModel>> allStores() async => List.unmodifiable(_stores);

  @override
  Future<StoreModel> createStore(StoreModel store) async {
    _stores.add(store);
    return store;
  }

  @override
  Future<StoreModel?> storeById(String storeId) async =>
      _find((s) => s.id == storeId);

  @override
  Future<StoreModel?> storeBySlug(String slug) async =>
      _find((s) => s.slug == slug);

  @override
  Future<List<StoreModel>> storesForSeller(String sellerId) async =>
      _stores.where((s) => s.sellerId == sellerId).toList();

  @override
  Future<void> updateStore(StoreModel store) async {
    final index = _stores.indexWhere((s) => s.id == store.id);
    if (index != -1) _stores[index] = store;
  }

  StoreModel? _find(bool Function(StoreModel store) predicate) {
    for (final store in _stores) {
      if (predicate(store)) return store;
    }
    return null;
  }
}
