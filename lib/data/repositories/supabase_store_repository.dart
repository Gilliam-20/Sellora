import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/store_model.dart';
import '../services/supabase_service.dart';
import 'store_repository.dart';

class SupabaseStoreRepository extends GetxService implements StoreRepository {
  final SupabaseService _db = Get.find<SupabaseService>();

  /// Set once at creation; the stores_guard_update trigger refuses changes.
  static const _immutable = {'id', 'slug', 'sellerId', 'createdAt'};

  @override
  Future<List<StoreModel>> allStores() async {
    final rows = await _db.stores.select();
    return rows.map((r) => StoreModel.fromMap(fromRow(r))).toList();
  }

  @override
  Future<StoreModel?> storeById(String storeId) async {
    final row = await _db.stores.select().eq('id', storeId).maybeSingle();
    return row == null ? null : StoreModel.fromMap(fromRow(row));
  }

  @override
  Future<StoreModel?> storeBySlug(String slug) async {
    final row = await _db.stores.select().eq('slug', slug).maybeSingle();
    return row == null ? null : StoreModel.fromMap(fromRow(row));
  }

  @override
  Future<List<StoreModel>> storesForSeller(String sellerId) async {
    final rows = await _db.stores.select().eq('seller_id', sellerId);
    return rows.map((r) => StoreModel.fromMap(fromRow(r))).toList();
  }

  @override
  Future<StoreModel> createStore(StoreModel store) async {
    // `stores.slug` is unique, so if the slug was taken since the caller's
    // storeBySlug() check, this insert fails outright — no duplicate slug
    // and no half-created store.
    final row = await _db.stores
        .insert(toRow(store.toMap()
          ..removeWhere((key, value) => key == 'createdAt' && value == null)))
        .select()
        .single();
    return StoreModel.fromMap(fromRow(row));
  }

  @override
  Future<void> updateStore(StoreModel store) async {
    await _db.stores
        .update(toRow(store.toMap(), omit: _immutable))
        .eq('id', store.id);
  }

  /// Each upload gets a fresh name rather than overwriting `logo.png`, so
  /// a storefront never serves a CDN-cached copy of the previous image.
  @override
  Future<String> uploadStoreImage(
    String storeId,
    Uint8List bytes, {
    required String contentType,
    required String kind,
  }) async {
    final ext = switch (contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      _ => 'jpg',
    };
    final path = '$storeId/$kind-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _db.storeMedia.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: contentType),
    );
    return _db.storeMedia.getPublicUrl(path);
  }
}
