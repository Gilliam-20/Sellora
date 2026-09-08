import 'package:get/get.dart';
import '../../../data/models/order_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/order_repository.dart';

class BuyerOrdersController extends GetxController {
  final OrderRepository _orderRepo = Get.find<OrderRepository>();
  final AuthRepository _authRepo = Get.find<AuthRepository>();

  final orders = <OrderModel>[].obs;
  final isLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    loadOrders();
  }

  Future<void> loadOrders() async {
    final user = _authRepo.cachedUser;
    if (user == null) return;
    isLoading.value = true;
    orders.value = await _orderRepo.buyerOrders(user.uid);
    isLoading.value = false;
  }
}
