import '../models/user_model.dart';

abstract class AdminRepository {
  Future<List<UserModel>> fetchSellers();
  Future<void> setSellerStatus(String sellerId, SellerStatus status);

  /// Pulls fresh products from CJ Dropshipping into the shared `catalog`
  /// collection sellers browse from. Returns how many products synced.
  Future<int> syncCjCatalog();
  DateTime? get lastSyncedAt;
}
