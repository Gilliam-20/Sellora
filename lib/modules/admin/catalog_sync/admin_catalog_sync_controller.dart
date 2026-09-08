import 'package:get/get.dart';
import '../../../data/repositories/admin_repository.dart';

class AdminCatalogSyncController extends GetxController {
  final AdminRepository _adminRepo = Get.find<AdminRepository>();

  final isSyncing = false.obs;
  final lastSyncCount = RxnInt();

  DateTime? get lastSyncedAt => _adminRepo.lastSyncedAt;

  Future<void> sync() async {
    isSyncing.value = true;
    try {
      final count = await _adminRepo.syncCjCatalog();
      lastSyncCount.value = count;
      Get.snackbar('Sync complete', '$count products pulled from CJ Dropshipping.');
    } finally {
      isSyncing.value = false;
    }
  }
}
