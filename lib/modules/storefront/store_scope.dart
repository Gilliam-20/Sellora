import 'package:get/get.dart';

import '../../data/models/store_model.dart';
import '../../data/repositories/store_repository.dart';

/// The single source of truth for the public storefront currently being
/// rendered. Route resolution is deliberately separate from UI so `/s/slug`
/// can later be replaced by a custom-domain resolver without leaking tenant
/// lookup details into product/order/customer features.
class StoreScope extends GetxService {
  StoreScope({StoreRepository? repository})
      : _storeRepository = repository ?? Get.find<StoreRepository>();

  final StoreRepository _storeRepository;
  final current = Rxn<StoreModel>();
  final isResolving = false.obs;
  final errorMessage = RxnString();

  Future<StoreModel?> resolveSlug(String slug) => _resolve(
        () => _storeRepository.storeBySlug(slug.trim().toLowerCase()),
        notFoundMessage: 'This storefront could not be found.',
      );

  /// Resolves the signed-in seller's own store for the seller-admin shell.
  /// A seller may own more than one store (`StoreRepository.storesForSeller`),
  /// but nothing in the product yet lets them create a second one or switch
  /// between them, so the first is treated as "the" active store until a
  /// store switcher exists — see WORKLOG.md decision #4.
  Future<StoreModel?> resolveForSeller(String sellerId) => _resolve(
        () async {
          final stores = await _storeRepository.storesForSeller(sellerId);
          return stores.isEmpty ? null : stores.first;
        },
        notFoundMessage: "You haven't created a store yet.",
      );

  Future<StoreModel?> _resolve(
    Future<StoreModel?> Function() lookup, {
    required String notFoundMessage,
  }) async {
    isResolving.value = true;
    errorMessage.value = null;
    try {
      final store = await lookup();
      current.value = store;
      if (store == null) {
        errorMessage.value = notFoundMessage;
      }
      return store;
    } catch (_) {
      current.value = null;
      errorMessage.value = 'We could not load this store. Please try again.';
      return null;
    } finally {
      isResolving.value = false;
    }
  }

  void clear() {
    current.value = null;
    errorMessage.value = null;
  }
}
