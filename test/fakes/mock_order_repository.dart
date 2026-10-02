import 'package:get/get.dart';
import 'package:sellora/data/models/order_model.dart';
import 'package:sellora/data/models/order_refund_model.dart';
import 'package:sellora/data/repositories/order_repository.dart';

class MockOrderRepository extends GetxService implements OrderRepository {
  final List<OrderModel> _orders = [];

  @override
  Future<OrderModel> placeOrder(OrderModel order) async {
    await Future.delayed(const Duration(milliseconds: 500));
    _orders.insert(0, order);
    return order;
  }

  @override
  Future<List<OrderModel>> buyerOrders(String buyerId) async {
    await Future.delayed(const Duration(milliseconds: 250));
    return _orders.where((o) => o.buyerId == buyerId).toList();
  }

  @override
  Future<List<OrderModel>> buyerStoreOrders(
      String buyerId, String storeId) async {
    await Future.delayed(const Duration(milliseconds: 250));
    return _orders
        .where((o) => o.buyerId == buyerId && o.storeId == storeId)
        .toList();
  }

  @override
  Future<List<OrderModel>> storeOrders(String storeId) async {
    await Future.delayed(const Duration(milliseconds: 250));
    return _orders.where((o) => o.storeId == storeId).toList();
  }

  @override
  Future<List<OrderModel>> sellerOrders(String sellerId) async {
    await Future.delayed(const Duration(milliseconds: 250));
    return _orders.where((o) => o.sellerId == sellerId).toList();
  }

  @override
  Future<List<OrderModel>> allOrders() async {
    await Future.delayed(const Duration(milliseconds: 250));
    return _orders;
  }

  @override
  Future<void> updateStatus(String orderId, OrderStatus status) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final index = _orders.indexWhere((o) => o.id == orderId);
    // copyWith (not a fresh OrderModel(...)) so paymentStatus and the fee
    // snapshot survive a fulfillment-status change — a hand-rebuilt
    // constructor here previously reset both to their zero defaults, which
    // silently corrupted a paid order's dashboard/analytics numbers the
    // moment a seller marked it shipped.
    if (index != -1) _orders[index] = _orders[index].copyWith(status: status);
  }

  /// Refunds recorded by [refundOrder], keyed by order id.
  final Map<String, double> refunded = {};

  @override
  Future<OrderRefundInfo?> refundInfo(String orderId) async {
    final order = _orders.firstWhereOrNull((o) => o.id == orderId);
    if (order == null) return null;
    return OrderRefundInfo(
      orderId: orderId,
      paymentProvider: 'INTASEND',
      paymentStatus: switch (order.paymentStatus) {
        OrderPaymentStatus.paid => 'paid',
        OrderPaymentStatus.partiallyRefunded => 'partially_refunded',
        OrderPaymentStatus.refunded => 'refunded',
        OrderPaymentStatus.failed => 'failed',
        OrderPaymentStatus.pending => 'pending',
      },
      chargedAmount: order.total,
      refundedAmount: refunded[orderId] ?? 0,
    );
  }

  @override
  Future<void> refundOrder(String orderId,
      {double? amount, String? reason, String? comment}) async {
    final info = await refundInfo(orderId);
    if (info == null) return;
    final total = (refunded[orderId] ?? 0) + (amount ?? info.remaining);
    refunded[orderId] = total;
    final index = _orders.indexWhere((o) => o.id == orderId);
    _orders[index] = _orders[index].copyWith(
        paymentStatus: total >= (info.chargedAmount ?? 0)
            ? OrderPaymentStatus.refunded
            : OrderPaymentStatus.partiallyRefunded);
  }
}
