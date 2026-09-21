import 'package:get/get.dart';
import '../../models/order_model.dart';
import '../order_repository.dart';

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
}
