import 'package:get/get.dart';
import '../../../data/models/activity_models.dart';
import '../../../data/repositories/admin_repository.dart';

/// Admin → Activity: the audit log (who changed what) and the app's
/// uncaught errors, grouped by fingerprint.
class AdminActivityController extends GetxController {
  AdminActivityController({AdminRepository? adminRepository})
      : _adminRepo = adminRepository ?? Get.find<AdminRepository>();

  final AdminRepository _adminRepo;

  final isLoading = true.obs;
  final errorMessage = RxnString();
  final auditEntries = <AuditLogEntry>[].obs;
  final errorGroups = <ClientErrorGroup>[].obs;

  /// Narrows the audit log to one entity type ('store', 'order', ...);
  /// null shows everything.
  final entityFilter = RxnString();

  List<String> get entityTypes =>
      auditEntries.map((e) => e.entityType).toSet().toList()..sort();

  List<AuditLogEntry> get visibleAudit {
    final filter = entityFilter.value;
    return filter == null
        ? auditEntries
        : auditEntries.where((e) => e.entityType == filter).toList();
  }

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final results = await Future.wait([
        _adminRepo.auditLog(),
        _adminRepo.clientErrors(),
      ]);
      auditEntries.assignAll(results[0] as List<AuditLogEntry>);
      errorGroups.assignAll(
          ClientErrorGroup.group(results[1] as List<ClientErrorReport>));
    } catch (_) {
      errorMessage.value = 'Activity couldn\'t be loaded.';
    } finally {
      isLoading.value = false;
    }
  }

  void filterEntity(String? type) => entityFilter.value = type;
}
