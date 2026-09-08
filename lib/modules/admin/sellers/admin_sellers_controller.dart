import 'package:get/get.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/admin_repository.dart';

class AdminSellersController extends GetxController {
  final AdminRepository _adminRepo = Get.find<AdminRepository>();

  final sellers = <UserModel>[].obs;
  final isLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    sellers.value = await _adminRepo.fetchSellers();
    isLoading.value = false;
  }

  Future<void> approve(String sellerId) async {
    await _adminRepo.setSellerStatus(sellerId, SellerStatus.active);
    load();
  }

  Future<void> suspend(String sellerId) async {
    await _adminRepo.setSellerStatus(sellerId, SellerStatus.suspended);
    load();
  }
}
