import 'package:get/get.dart';
import '../../../data/models/store_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../data/repositories/store_repository.dart';

class AdminStoresController extends GetxController {
  AdminStoresController({
    StoreRepository? storeRepository,
    AdminRepository? adminRepository,
  })  : _storeRepo = storeRepository ?? Get.find<StoreRepository>(),
        _adminRepo = adminRepository ?? Get.find<AdminRepository>();

  final StoreRepository _storeRepo;
  final AdminRepository _adminRepo;

  final isLoading = true.obs;

  /// The store id a suspend/lift is in flight for.
  final updatingStoreId = RxnString();
  final stores = <StoreModel>[].obs;
  final sellers = <UserModel>[].obs;
  final query = ''.obs;

  List<StoreModel> get filtered {
    if (query.value.trim().isEmpty) return stores;
    final q = query.value.trim().toLowerCase();
    return stores
        .where((s) =>
            s.name.toLowerCase().contains(q) ||
            s.slug.toLowerCase().contains(q) ||
            sellerFor(s)?.name.toLowerCase().contains(q) == true ||
            sellerFor(s)?.email.toLowerCase().contains(q) == true)
        .toList();
  }

  UserModel? sellerFor(StoreModel store) =>
      sellers.firstWhereOrNull((s) => s.uid == store.sellerId);

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    final results = await Future.wait([
      _storeRepo.allStores(),
      _adminRepo.fetchSellers(),
    ]);
    stores.assignAll(results[0] as List<StoreModel>);
    sellers.value = results[1] as List<UserModel>;
    isLoading.value = false;
  }

  void setQuery(String value) => query.value = value;

  /// Suspends [store] (with [reason], shown to the seller) or lifts its
  /// suspension. Returns an error message, or null on success.
  Future<String?> setSuspended(StoreModel store,
      {required bool suspended, String? reason}) async {
    final trimmed = reason?.trim();
    if (suspended && (trimmed == null || trimmed.isEmpty)) {
      return 'Give the seller a reason.';
    }
    updatingStoreId.value = store.id;
    try {
      await _adminRepo.setStoreSuspended(store.id,
          suspended: suspended, reason: trimmed);
      final index = stores.indexWhere((s) => s.id == store.id);
      if (index != -1) {
        stores[index] = StoreModel.fromMap({
          ...store.toMap(),
          'isSuspended': suspended,
          'suspensionReason': suspended ? trimmed : null,
          'suspendedAt': suspended ? DateTime.now().toIso8601String() : null,
        });
      }
      return null;
    } catch (_) {
      return suspended
          ? 'The store couldn\'t be suspended.'
          : 'The suspension couldn\'t be lifted.';
    } finally {
      updatingStoreId.value = null;
    }
  }
}
