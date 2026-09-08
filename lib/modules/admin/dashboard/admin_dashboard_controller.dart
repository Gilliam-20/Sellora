import 'package:get/get.dart';
import '../../../data/models/order_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../data/repositories/order_repository.dart';

class AdminDashboardController extends GetxController {
  final AdminRepository _adminRepo = Get.find<AdminRepository>();
  final OrderRepository _orderRepo = Get.find<OrderRepository>();

  final isLoading = true.obs;
  final sellers = <UserModel>[].obs;
  final orders = <OrderModel>[].obs;

  int get activeSellerCount =>
      sellers.where((s) => s.sellerStatus == SellerStatus.active).length;
  int get pendingSellerCount => sellers
      .where((s) => s.sellerStatus == SellerStatus.pendingApproval)
      .length;
  double get totalGmv => orders.fold(0.0, (sum, o) => sum + o.total);

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    sellers.value = await _adminRepo.fetchSellers();
    orders.value = await _orderRepo.allOrders();
    isLoading.value = false;
  }
}
