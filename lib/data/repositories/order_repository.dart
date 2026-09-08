import '../models/order_model.dart';

abstract class OrderRepository {
  Future<OrderModel> placeOrder(OrderModel order);
  Future<List<OrderModel>> buyerOrders(String buyerId);

  /// Same as [buyerOrders], additionally scoped to one store — what the
  /// buyer-facing order history screen uses now that a buyer is a
  /// customer of a single store.
  Future<List<OrderModel>> buyerStoreOrders(String buyerId, String storeId);
  Future<List<OrderModel>> sellerOrders(String sellerId);
  Future<List<OrderModel>> allOrders(); // admin oversight
  Future<void> updateStatus(String orderId, OrderStatus status);
}
