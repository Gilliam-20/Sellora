import 'package:get/get.dart';
import '../../../data/models/store_model.dart';
import '../../../data/repositories/store_repository.dart';

/// Backs [StoreSelectView] — the demo-mode stand-in for arriving at a
/// store's own `sellora.app/s/{slug}` URL. Lists every store so a
/// prospective buyer can pick one to register under.
class StoreSelectController extends GetxController {
  final StoreRepository _storeRepo = Get.find<StoreRepository>();

  final stores = <StoreModel>[].obs;
  final isLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  Future<void> _load() async {
    isLoading.value = true;
    stores.value = await _storeRepo.allStores();
    isLoading.value = false;
  }
}
