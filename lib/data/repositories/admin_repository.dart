import '../models/user_model.dart';

abstract class AdminRepository {
  Future<List<UserModel>> fetchSellers();
  Future<void> setSellerStatus(String sellerId, SellerStatus status);

  /// Triggers the server-side CJ catalog/category sync (writes the shared
  /// `catalog_products`/`catalog_categories` tables with the service role —
  /// see supabase/functions/api/index.ts's `runCatalogSync`). Returns how
  /// many products were written this run.
  Future<int> syncCjCatalog();
  DateTime? get lastSyncedAt;
}
