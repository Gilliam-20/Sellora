import 'package:get/get.dart';
import '../../../data/models/order_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/order_repository.dart';

class SellerOrdersController extends GetxController {
  final OrderRepository _orderRepo = Get.find<OrderRepository>();
  final AuthRepository _authRepo = Get.find<AuthRepository>();

  final orders = <OrderModel>[].obs;
  final isLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    final user = _authRepo.cachedUser;
    if (user == null) return;
    isLoading.value = true;
    orders.value = await _orderRepo.sellerOrders(user.uid);
    isLoading.value = false;
  }

  Future<void> advanceStatus(OrderModel order) async {
    final next = switch (order.status) {
      OrderStatus.pending => OrderStatus.processing,
      OrderStatus.processing => OrderStatus.shipped,
      OrderStatus.shipped => OrderStatus.delivered,
      OrderStatus.delivered => OrderStatus.delivered,
      OrderStatus.cancelled => OrderStatus.cancelled,
    };
    if (next == order.status) return;
    await _orderRepo.updateStatus(order.id, next);
    load();
  }
}
