import '../models/store_model.dart';

abstract class StoreRepository {
  /// Every store on the platform — backs the buyer-facing store picker
  /// today; admin cross-store oversight later.
  Future<List<StoreModel>> allStores();

  Future<StoreModel?> storeById(String storeId);

  /// Resolves the human-friendly handle used in a store's public URL.
  Future<StoreModel?> storeBySlug(String slug);

  /// A seller's own stores (a seller can own more than one).
  Future<List<StoreModel>> storesForSeller(String sellerId);

  Future<StoreModel> createStore(StoreModel store);

  Future<void> updateStore(StoreModel store);
}
