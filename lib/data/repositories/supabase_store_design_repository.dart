import 'package:get/get.dart';
import '../models/store_design.dart';
import '../services/supabase_service.dart';
import 'store_design_repository.dart';

class SupabaseStoreDesignRepository extends GetxService
    implements StoreDesignRepository {
  final SupabaseService _db = Get.find<SupabaseService>();

  @override
  Future<StoreDesign?> publishedDesign(String storeId) async {
    final row = await _db.storefrontDesigns
        .select('design')
        .eq('store_id', storeId)
        .maybeSingle();
    final design = row?['design'];
    return design is Map
        ? StoreDesign.fromMap(Map<String, dynamic>.from(design))
        : null;
  }

  @override
  Future<StoreDesignRecord?> loadForOwner(String storeId) async {
    final row =
        await _db.storeDesigns.select().eq('store_id', storeId).maybeSingle();
    if (row == null) return null;
    final r = fromRow(row);
    StoreDesign? read(Object? raw) =>
        raw is Map ? StoreDesign.fromMap(Map<String, dynamic>.from(raw)) : null;
    final published = read(r['published']);
    return StoreDesignRecord(
      draft: read(r['draft']) ?? published ?? const StoreDesign(sections: []),
      published: published,
      publishedAt: DateTime.tryParse(r['publishedAt'] as String? ?? ''),
      publishedVersion: (r['publishedVersion'] as num?)?.toInt() ?? 0,
      draftUpdatedAt: DateTime.tryParse(r['draftUpdatedAt'] as String? ?? ''),
    );
  }

  /// Update, else insert: the client may write only `draft` (and
  /// `store_id` on insert), so an upsert, which would also update
  /// `store_id`, is refused.
  @override
  Future<void> saveDraft(String storeId, StoreDesign draft) async {
    final updated = await _db.storeDesigns
        .update({'draft': draft.toMap()})
        .eq('store_id', storeId)
        .select('store_id');
    if (updated.isEmpty) {
      await _db.storeDesigns
          .insert({'store_id': storeId, 'draft': draft.toMap()});
    }
  }

  @override
  Future<int> publish(String storeId) async {
    final res = await _db.client
        .rpc('publish_store_design', params: {'p_store_id': storeId});
    return ((res as Map)['version'] as num).toInt();
  }

  @override
  Future<void> subscribeToNewsletter(String storeId, String email) async {
    await _db.client.rpc('subscribe_to_store_newsletter',
        params: {'p_store_id': storeId, 'p_email': email});
  }

  @override
  Future<List<NewsletterSubscriber>> subscribers(String storeId) async {
    final rows = await _db.newsletterSubscribers
        .select('id, email, created_at')
        .eq('store_id', storeId)
        .order('created_at', ascending: false)
        .limit(1000);
    return [
      for (final r in rows)
        NewsletterSubscriber(
          id: (r['id'] as num).toInt(),
          email: r['email'] as String,
          createdAt:
              DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal() ??
                  DateTime.now(),
        ),
    ];
  }

  @override
  Future<void> removeSubscriber(int id) async {
    await _db.newsletterSubscribers.delete().eq('id', id);
  }
}
