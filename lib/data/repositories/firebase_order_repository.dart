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
    // Cloud Function re-prices every item from CJ's own live price itself,
    // so a tampered `order.total`/fee field here is simply ignored. See
    // functions/lib/orders.js's createOrder and firestore.rules (`orders`
    // create is `if false`).
    //
    // `pid`/`vid` per item is now correct — [OrderItem.cjProductId] and
    // [OrderItem.variantId] carry CJ's own ids all the way from the
    // catalog/variant model. Still unreconciled, and NOT fixed by this
    // wiring pass: `shippingAddress` needs to be `{countryCode, ...}`, not
    // a free-text string (see CheckoutController, which only collects the
    // latter), and the response below reads `orderId`/`code`/
    // `serviceFeeAmount` — fields the adopted single-vendor backend's
    // `createOrder` doesn't return (it returns `{id, totalAmount, currency,
    // items, ...}` with no seller/fee/store concept at all). Both need a
    // real reconciliation pass, not a mechanical fix.
    final res = await _dio.post(ApiEndpoints.createOrder, data: {
      'items': order.items
          .map((i) => {
                'pid': i.cjProductId ?? i.productId,
                'vid': i.variantId,
                'quantity': i.quantity,
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
