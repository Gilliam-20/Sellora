import 'package:get/get.dart';
import '../../models/store_model.dart';
import '../../mock/mock_seed_data.dart';
import '../store_repository.dart';

class MockStoreRepository extends GetxService implements StoreRepository {
  final List<StoreModel> _stores = MockSeedData.stores();

  @override
  Future<List<StoreModel>> allStores() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return List.unmodifiable(_stores);
  }

  @override
  Future<StoreModel?> storeById(String storeId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final matches = _stores.where((s) => s.id == storeId);
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<StoreModel?> storeBySlug(String slug) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final matches = _stores.where((s) => s.slug == slug);
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<List<StoreModel>> storesForSeller(String sellerId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return _stores.where((s) => s.sellerId == sellerId).toList();
  }

  @override
  Future<StoreModel> createStore(StoreModel store) async {
    await Future.delayed(const Duration(milliseconds: 200));
    _stores.add(store);
    return store;
  }

  @override
  Future<void> updateStore(StoreModel store) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final index = _stores.indexWhere((s) => s.id == store.id);
    if (index != -1) _stores[index] = store;
  }
}
