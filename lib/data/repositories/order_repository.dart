import '../models/order_model.dart';
import '../models/order_refund_model.dart';

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

  /// Admin only. An order's charged amount and refund history, or null if
  /// the caller can't see it.
  Future<OrderRefundInfo?> refundInfo(String orderId);

  /// Admin only. Refunds [amount] (everything left when null) through the
  /// order's payment provider. Throws an ApiException carrying the server's
  /// reason when the refund is refused or the provider rejects it.
  Future<void> refundOrder(String orderId,
      {double? amount, String? reason, String? comment});
}
