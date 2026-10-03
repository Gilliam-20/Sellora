import '../models/store_page.dart';

/// A storefront's own pages (TODO §20): About, Contact and the policies.
abstract class StorePageRepository {
  /// What buyers see: [storeId]'s published pages, by kind. Empty for a
  /// suspended store or one whose seller can't sell.
  Future<Map<StorePageKind, StorePage>> publishedPages(String storeId);

  /// Every page the owner has saved, published or not.
  Future<Map<StorePageKind, StorePage>> ownerPages(String storeId);

  /// Creates or replaces [page] for [storeId].
  Future<void> savePage(String storeId, StorePage page);

  Future<void> deletePage(String storeId, StorePageKind kind);
}
