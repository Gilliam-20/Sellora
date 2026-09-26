import 'dart:typed_data';

import '../../core/utils/slug.dart';
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

  /// Uploads a branding image ([kind] is `logo` or `banner`) for
  /// [storeId] and returns its public URL, to store in
  /// `StoreModel.logoUrl`/`bannerUrl`. Only the store's owner may upload
  /// (storage RLS in supabase/migrations/20260927000200_storage.sql).
  Future<String> uploadStoreImage(
    String storeId,
    Uint8List bytes, {
    required String contentType,
    required String kind,
  });
}

/// Creates a seller's store under the first free slug derived from
/// [storeName] (`my-shop`, `my-shop-2`, ...). Shared by both auth
/// repositories' sign-up and onboarding's "create your store" recovery path,
/// so every store creation reserves its slug the same way. The id is
/// `store-{sellerId}` — one store per seller until decision #4 (see
/// WORKLOG.md) settles multi-store.
Future<StoreModel> createStoreForSeller(
  StoreRepository repository, {
  required String sellerId,
  required String storeName,
  String? category,
  String? countryCode,
  String currencyCode = 'KES',
}) async {
  final base = slugify(storeName);
  var slug = base;
  var suffix = 2;
  while (await repository.storeBySlug(slug) != null) {
    slug = '$base-$suffix';
    suffix++;
  }
  return repository.createStore(StoreModel(
    id: 'store-$sellerId',
    slug: slug,
    sellerId: sellerId,
    name: storeName,
    category: category,
    countryCode: countryCode,
    currencyCode: currencyCode,
    createdAt: DateTime.now(),
  ));
}
