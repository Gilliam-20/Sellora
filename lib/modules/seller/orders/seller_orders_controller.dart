import 'package:get/get.dart';
import '../../../data/models/order_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../data/repositories/notification_repository.dart';

class SellerOrdersController extends GetxController {
  final OrderRepository _orderRepo = Get.find<OrderRepository>();
  final AuthRepository _authRepo = Get.find<AuthRepository>();
  final NotificationRepository _notificationRepo =
      Get.find<NotificationRepository>();

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

  /// The status a seller may move [order] to, or null. Only a paid order
  /// moves, and only forward through fulfilment — the server enforces the
  /// same rule (the `orders_guard_status` trigger). A paid order becomes
  /// `processing` on its own when payment is confirmed, and cancelling one
  /// is the admin refund path, so it refunds the buyer.
  static OrderStatus? nextStatus(OrderModel order) {
    if (order.paymentStatus != OrderPaymentStatus.paid) return null;
    return switch (order.status) {
      OrderStatus.processing => OrderStatus.shipped,
      OrderStatus.shipped => OrderStatus.delivered,
      _ => null,
    };
  }

  Future<void> advanceStatus(OrderModel order) async {
    final next = nextStatus(order);
    if (next == null) return;
    await _orderRepo.updateStatus(order.id, next);
    await _notificationRepo.notifyOrderStatusChanged(order.copyWith(status: next));
    load();
  }
}
