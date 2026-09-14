import '../models/user_model.dart';

abstract class AdminRepository {
  Future<List<UserModel>> fetchSellers();
  Future<void> setSellerStatus(String sellerId, SellerStatus status);

  /// Triggers the server-side CJ catalog/category sync (writes Firestore's
  /// shared `products`/`categories` collections directly via Admin SDK —
  /// see functions/index.js's `runCatalogSync`). Returns how many products
  /// were written this run.
  Future<int> syncCjCatalog();
  DateTime? get lastSyncedAt;
}
