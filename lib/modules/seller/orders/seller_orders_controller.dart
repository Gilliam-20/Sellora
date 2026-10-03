import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../data/models/order_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import 'order_filters.dart';

class SellerOrdersController extends GetxController {
  final OrderRepository _orderRepo = Get.find<OrderRepository>();
  final AuthRepository _authRepo = Get.find<AuthRepository>();
  final NotificationRepository _notificationRepo =
      Get.find<NotificationRepository>();

  final orders = <OrderModel>[].obs;
  final isLoading = true.obs;
  final errorMessage = RxnString();

  final filter = OrderFilter.all.obs;
  final query = ''.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    final user = _authRepo.cachedUser;
    if (user == null) return;
    isLoading.value = true;
    errorMessage.value = null;
    try {
      orders.value = await _orderRepo.sellerOrders(user.uid);
    } catch (e) {
      errorMessage.value = 'We couldn\'t load your orders. $e';
    } finally {
      isLoading.value = false;
    }
  }

  /// [orders] narrowed by [filter] and [query], newest first as loaded.
  List<OrderModel> get visibleOrders => orders
      .where((o) => filter.value.matches(o) && o.matchesQuery(query.value))
      .toList();

  /// How many orders each filter would show, for the chip counts.
  int countFor(OrderFilter f) => orders.where(f.matches).length;

  void openDetail(OrderModel order) async {
    await Get.toNamed(Routes.sellerOrderDetail, arguments: order);
    // The detail screen can ship, cancel or annotate the order.
    load();
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
