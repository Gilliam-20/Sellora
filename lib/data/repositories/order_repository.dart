import '../models/order_model.dart';

abstract class OrderRepository {
  Future<OrderModel> placeOrder(OrderModel order);
  Future<List<OrderModel>> buyerOrders(String buyerId);

  /// Same as [buyerOrders], additionally scoped to one store — what the
  /// buyer-facing order history screen uses now that a buyer is a
  /// customer of a single store.
  Future<List<OrderModel>> buyerStoreOrders(String buyerId, String storeId);

  /// Every order placed against one store, for that store's own order
  /// queue. Reads `stores/{storeId}/orders` once `placeOrder` writes there;
  /// until that write-path migration lands this returns whatever the flat
  /// `orders` collection has for the store (see WORKLOG.md).
  Future<List<OrderModel>> storeOrders(String storeId);
  Future<List<OrderModel>> sellerOrders(String sellerId);
  Future<List<OrderModel>> allOrders(); // admin oversight
  Future<void> updateStatus(String orderId, OrderStatus status);
}
