import '../models/order_model.dart';

abstract class OrderRepository {
  Future<OrderModel> placeOrder(OrderModel order);
  Future<List<OrderModel>> buyerOrders(String buyerId);
  Future<List<OrderModel>> sellerOrders(String sellerId);
  Future<List<OrderModel>> allOrders(); // admin oversight
  Future<void> updateStatus(String orderId, OrderStatus status);
}
