import 'package:get/get.dart';

import '../models/store_page.dart';
import '../services/supabase_service.dart';
import 'store_page_repository.dart';

class SupabaseStorePageRepository extends GetxService
    implements StorePageRepository {
  final SupabaseService _db = Get.find<SupabaseService>();

  Map<StorePageKind, StorePage> _byKind(List<Map<String, dynamic>> rows) => {
        for (final row in rows)
          if (StorePage.tryFromMap(fromRow(row)) case final page?)
            page.kind: page,
      };

  @override
  Future<Map<StorePageKind, StorePage>> publishedPages(String storeId) async =>
      _byKind(await _db.storefrontPages.select().eq('store_id', storeId));

  @override
  Future<Map<StorePageKind, StorePage>> ownerPages(String storeId) async =>
      _byKind(await _db.storePages.select().eq('store_id', storeId));

  /// Update, else insert: the client may not write `store_id` or `kind` on
  /// update, so an upsert would be refused.
  @override
  Future<void> savePage(String storeId, StorePage page) async {
    final row = toRow(page.toMap());
    final changes = Map.of(row)..remove('kind');
    final updated = await _db.storePages
        .update(changes)
        .eq('store_id', storeId)
        .eq('kind', page.kind.id)
        .select('kind');
    if (updated.isEmpty) {
      await _db.storePages.insert({...row, 'store_id': storeId});
    }
  }

  @override
  Future<void> deletePage(String storeId, StorePageKind kind) =>
      _db.storePages.delete().eq('store_id', storeId).eq('kind', kind.id);
}
