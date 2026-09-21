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
    // `pid`/`vid` per item is correct — [OrderItem.cjProductId] and
    // [OrderItem.variantId] carry CJ's own ids all the way from the
    // catalog/variant model. `shippingAddress` now sends the
    // `{countryCode, line}` shape `createOrder` requires (see
    // [ShippingAddress]). `storeId`/`paymentMethod`/`currency` are sent for
    // this app's own bookkeeping only — the adopted single-vendor backend
    // ignores all three: it has no seller/store/fee concept, and derives
    // `currency` itself from `shippingAddress.countryCode`.
    final res = await _dio.post(ApiEndpoints.createOrder, data: {
      'items': order.items
          .map((i) => {
                'pid': i.cjProductId ?? i.productId,
                'vid': i.variantId,
                'quantity': i.quantity,
              })
          .toList(),
      'shippingAddress': order.shippingAddress.toMap(),
      'storeId': order.storeId,
      'paymentMethod': order.paymentMethod,
      'currency': order.currency,
      // The buyer's checkout pick (see CheckoutController.selectShippingOption).
      // createOrder re-validates it against CJ's own freight quote and only
      // ever trusts the name, never a price - omit it to auto-pick cheapest.
      if (order.logisticName != null) 'logisticName': order.logisticName,
    });

    // The real response is `{id, totalAmount, currency, items, ...}` — no
    // `orderId`/`code`/`serviceFeeAmount` (no seller/fee/store concept at
    // all). There's no human-readable code either, so the order id doubles
    // as one. The response's own `items` lack imageUrl/variantLabel, so
    // this keeps the richer client-built list rather than overwriting it —
    // only the fields the server actually recomputed are trusted here.
    return order.copyWith(
      id: res['id'] as String,
      code: res['id'] as String,
      total: (res['totalAmount'] as num).toDouble(),
      currency: res['currency'] as String?,
      paymentStatus: OrderPaymentStatus.pending,
      logisticName: res['logisticName'] as String?,
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
    final snap = await _fs
        .storeOrders(storeId)
        .orderBy('createdAt', descending: true)
        .get();
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
