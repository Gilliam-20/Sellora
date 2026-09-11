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

  Future<StoreModel?> resolveSlug(String slug) async {
    isResolving.value = true;
    errorMessage.value = null;
    try {
      final store = await _storeRepository.storeBySlug(slug.trim().toLowerCase());
      current.value = store;
      if (store == null) {
        errorMessage.value = 'This storefront could not be found.';
      }
      return store;
    } catch (_) {
      current.value = null;
      errorMessage.value = 'We could not load this storefront. Please try again.';
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
