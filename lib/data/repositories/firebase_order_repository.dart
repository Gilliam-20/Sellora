import 'package:get/get.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/dio_client.dart';
import '../models/order_model.dart';
import '../services/firestore_service.dart';
import 'order_repository.dart';

class FirebaseOrderRepository extends GetxService implements OrderRepository {
  final FirestoreService _fs = Get.find<FirestoreService>();
  final DioClient _dio = Get.find<DioClient>();

  @override
  Future<OrderModel> placeOrder(OrderModel order) async {
    // The order doc is never written directly from the client — the
    // Cloud Function re-reads each listing's price/seller itself, so a
    // tampered `order.total`/`sellerId`/fee field here is simply ignored.
    // See functions/src/orders.ts's createOrder and firestore.rules
    // (`orders` create is `if false`).
    final res = await _dio.post(ApiEndpoints.createOrder, data: {
      'items': order.items
          .map((i) => {
                'productId': i.productId,
                'quantity': i.quantity,
                'variant': i.variant,
              })
          .toList(),
      'shippingAddress': order.shippingAddress,
      'storeId': order.storeId,
      'paymentMethod': order.paymentMethod,
      'currency': order.currency,
    });

    return order.copyWith(
      id: res['orderId'] as String,
      code: res['code'] as String,
      total: (res['total'] as num).toDouble(),
      serviceFeeAmount: (res['serviceFeeAmount'] as num).toDouble(),
      paymentStatus: OrderPaymentStatus.pending,
    );
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
