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
    if (user == null) {
      // A guest browsing this store has no orders to show — leave the list
      // empty and stop loading instead of hanging on a spinner forever.
      orders.clear();
      isLoading.value = false;
      return;
    }
    isLoading.value = true;
    orders.value = user.storeId != null
        ? await _orderRepo.buyerStoreOrders(user.uid, user.storeId!)
        : await _orderRepo.buyerOrders(user.uid);
    isLoading.value = false;
  }
}
