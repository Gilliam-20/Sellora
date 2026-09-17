import 'package:flutter_test/flutter_test.dart';
import 'package:sellora/data/models/store_model.dart';
import 'package:sellora/data/repositories/mock/mock_auth_repository.dart';
import 'package:sellora/data/repositories/store_repository.dart';

void main() {
  test('signUpSeller creates a store for the new seller', () async {
    final storeRepo = _FakeStoreRepository();
    final auth = MockAuthRepository(storeRepository: storeRepo);

    final user = await auth.signUpSeller(
      name: 'Amina',
      email: 'amina@example.com',
      password: 'password123',
      storeName: "Amina's Curated Picks",
      phone: '0712345678',
      hasAcceptedTerms: true,
    );

    final stores = await storeRepo.storesForSeller(user.uid);
    expect(stores, hasLength(1));
    expect(stores.single.sellerId, user.uid);
    expect(stores.single.slug, 'aminas-curated-picks');
  });

  test('signUpSeller de-duplicates a slug already taken by another store',
      () async {
    final storeRepo = _FakeStoreRepository()
      ..seed(StoreModel(
        id: 'store-existing',
        slug: 'aminas-store',
        sellerId: 'someone-else',
        name: "Amina's Store",
      ));
    final auth = MockAuthRepository(storeRepository: storeRepo);

    final user = await auth.signUpSeller(
      name: 'Amina',
      email: 'amina2@example.com',
      password: 'password123',
      storeName: "Amina's Store",
      phone: '0712345678',
      hasAcceptedTerms: true,
    );

    final stores = await storeRepo.storesForSeller(user.uid);
    expect(stores.single.slug, 'aminas-store-2');
  });

  test('signUpSeller records the agreed seller terms version', () async {
    final auth = MockAuthRepository(storeRepository: _FakeStoreRepository());

    final user = await auth.signUpSeller(
      name: 'Amina',
      email: 'amina@example.com',
      password: 'password123',
      storeName: "Amina's Store",
      phone: '0712345678',
      hasAcceptedTerms: true,
    );

    expect(user.sellerTermsAcceptedAt, isNotNull);
    expect(user.sellerTermsVersion, sellerTermsVersion);
  });

  test('signUpSeller rejects registration without terms acceptance', () async {
    final auth = MockAuthRepository(storeRepository: _FakeStoreRepository());

    await expectLater(
      auth.signUpSeller(
        name: 'Amina',
        email: 'amina@example.com',
        password: 'password123',
        storeName: "Amina's Store",
        phone: '0712345678',
        hasAcceptedTerms: false,
      ),
      throwsArgumentError,
    );
  });
}

class _FakeStoreRepository implements StoreRepository {
  final List<StoreModel> _stores = [];

  void seed(StoreModel store) => _stores.add(store);

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
