import 'package:flutter_test/flutter_test.dart';
import 'package:sellora/data/models/store_model.dart';
import 'package:sellora/data/repositories/store_repository.dart';
import 'package:sellora/modules/storefront/store_scope.dart';

void main() {
  final amina = StoreModel(
    id: 'store-a',
    slug: 'aminas-picks',
    sellerId: 'seller-a',
    name: "Amina's Picks",
  );
  final jengo = StoreModel(
    id: 'store-b',
    slug: 'jengo-electronics',
    sellerId: 'seller-b',
    name: 'Jengo Electronics',
  );

  test('resolves a slug and replaces, rather than mixes, the active tenant',
      () async {
    final scope = StoreScope(repository: _FakeStoreRepository([amina, jengo]));

    await scope.resolveSlug('AMINAS-PICKS');
    expect(scope.current.value?.id, 'store-a');
    expect(scope.errorMessage.value, isNull);

    await scope.resolveSlug('jengo-electronics');
    expect(scope.current.value?.id, 'store-b');
    expect(scope.current.value?.sellerId, 'seller-b');
  });

  test('clears the active tenant for an unknown slug', () async {
    final scope = StoreScope(repository: _FakeStoreRepository([amina]));
    await scope.resolveSlug(amina.slug);

    final result = await scope.resolveSlug('does-not-exist');

    expect(result, isNull);
    expect(scope.current.value, isNull);
    expect(scope.errorMessage.value, 'This storefront could not be found.');
  });
}

class _FakeStoreRepository implements StoreRepository {
  _FakeStoreRepository(this._stores);

  final List<StoreModel> _stores;

  @override
  Future<List<StoreModel>> allStores() async => _stores;

  @override
  Future<StoreModel> createStore(StoreModel store) async => store;

  @override
  Future<StoreModel?> storeById(String storeId) async =>
      _find((store) => store.id == storeId);

  @override
  Future<StoreModel?> storeBySlug(String slug) async =>
      _find((store) => store.slug == slug);

  @override
  Future<List<StoreModel>> storesForSeller(String sellerId) async =>
      _stores.where((store) => store.sellerId == sellerId).toList();

  @override
  Future<void> updateStore(StoreModel store) async {}

  StoreModel? _find(bool Function(StoreModel store) predicate) {
    for (final store in _stores) {
      if (predicate(store)) return store;
    }
    return null;
  }
}
