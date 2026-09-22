import 'package:get/get.dart';
import '../../../data/models/store_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../data/repositories/store_repository.dart';

class AdminStoresController extends GetxController {
  final StoreRepository _storeRepo = Get.find<StoreRepository>();
  final AdminRepository _adminRepo = Get.find<AdminRepository>();

  final isLoading = true.obs;
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
    stores.value = results[0] as List<StoreModel>;
    sellers.value = results[1] as List<UserModel>;
    isLoading.value = false;
  }

  void setQuery(String value) => query.value = value;
}
