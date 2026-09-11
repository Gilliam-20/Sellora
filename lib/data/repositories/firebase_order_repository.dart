import 'package:get/get.dart';
import '../models/order_model.dart';
import '../services/firestore_service.dart';
import 'order_repository.dart';

class FirebaseOrderRepository extends GetxService implements OrderRepository {
  final FirestoreService _fs = Get.find<FirestoreService>();

  @override
  Future<OrderModel> placeOrder(OrderModel order) async {
    await _fs.orders.doc(order.id).set(order.toMap());
    // Real fulfillment (CjDropshippingService.createFulfillmentOrder) is
    // triggered from a Cloud Function on order-create so it only ever
    // runs after payment is confirmed server-side — see
    // /functions/src/orders.ts.
    return order;
  }

  @override
  Future<List<OrderModel>> buyerOrders(String buyerId) async {
    final snap = await _fs.orders
        .where('buyerId', isEqualTo: buyerId)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) => OrderModel.fromMap(d.data())).toList();
  }

  @override
  Future<List<OrderModel>> buyerStoreOrders(
      String buyerId, String storeId) async {
    final snap = await _fs.orders
        .where('buyerId', isEqualTo: buyerId)
        .where('storeId', isEqualTo: storeId)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) => OrderModel.fromMap(d.data())).toList();
  }

  @override
  Future<List<OrderModel>> storeOrders(String storeId) async {
    final snap =
        await _fs.storeOrders(storeId).orderBy('createdAt', descending: true).get();
    return snap.docs.map((d) => OrderModel.fromMap(d.data())).toList();
  }

  @override
  Future<List<OrderModel>> sellerOrders(String sellerId) async {
    final snap = await _fs.orders
        .where('sellerId', isEqualTo: sellerId)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) => OrderModel.fromMap(d.data())).toList();
  }

  @override
  Future<List<OrderModel>> allOrders() async {
    final snap = await _fs.orders
        .orderBy('createdAt', descending: true)
        .limit(200)
        .get();
    return snap.docs.map((d) => OrderModel.fromMap(d.data())).toList();
  }

  @override
  Future<void> updateStatus(String orderId, OrderStatus status) async {
    await _fs.orders.doc(orderId).update({'status': status.name});
  }
}
