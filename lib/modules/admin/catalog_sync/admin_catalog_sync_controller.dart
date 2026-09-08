import 'package:get/get.dart';
import '../../../data/repositories/admin_repository.dart';

class AdminCatalogSyncController extends GetxController {
  final AdminRepository _adminRepo = Get.find<AdminRepository>();

  final isSyncing = false.obs;
  final lastSyncCount = RxnInt();

  // Rx wrapper around the repo's plain getter: reading a non-Rx value
  // inside an Obx gives no reactivity, so the "Last synced ..." label
  // was never updating after a sync completed. Refreshed explicitly
  // below instead.
  final lastSyncedAt = Rxn<DateTime>();

  @override
  void onInit() {
    super.onInit();
    lastSyncedAt.value = _adminRepo.lastSyncedAt;
  }

  Future<void> sync() async {
    isSyncing.value = true;
    try {
      final count = await _adminRepo.syncCjCatalog();
      lastSyncCount.value = count;
      lastSyncedAt.value = _adminRepo.lastSyncedAt;
      Get.snackbar('Sync complete', '$count products pulled from CJ Dropshipping.');
    } finally {
      isSyncing.value = false;
    }
  }
}
