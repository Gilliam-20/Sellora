import 'package:get/get.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/dio_client.dart';
import '../models/order_model.dart';
import '../services/supabase_service.dart';
import 'order_repository.dart';

class SupabaseOrderRepository extends GetxService implements OrderRepository {
  final SupabaseService _db = Get.find<SupabaseService>();
  final DioClient _dio = Get.find<DioClient>();

  @override
  Future<OrderModel> placeOrder(OrderModel order) async {
    // The order row is never written directly from the client — the
    // backend re-prices every item from CJ's own live price and the store's
    // own listed price itself, so a tampered `order.total`/fee field here is
    // simply ignored. See functions/lib/orders.js's createOrder, and the
    // `orders` table having no insert policy (supabase/migrations).
    //
    // `pid`/`vid` per item is correct — [OrderItem.cjProductId] and
    // [OrderItem.variantId] carry CJ's own ids all the way from the
    // catalog/variant model. `shippingAddress` sends the
    // `{countryCode, line}` shape `createOrder` requires (see
    // [ShippingAddress]). `storeId` is required — the server re-derives
    // `sellerId`/the fee split from it. `paymentMethod` is sent for this
    // app's own bookkeeping only; `currency` is sent but the server derives
    // its own from `shippingAddress.countryCode` and returns that instead.
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

    // The real response is `{id, totalAmount, currency, serviceFeeRate,
    // serviceFeeAmount, sellerRevenue, items, ...}` — no `orderId`/`code`,
    // so the order id doubles as one. The response's own `items` lack
    // imageUrl/variantLabel, so this keeps the richer client-built list
    // rather than overwriting it — only the fields the server actually
    // recomputed are trusted here.
    return order.copyWith(
      id: res['id'] as String,
      code: res['id'] as String,
      total: (res['totalAmount'] as num).toDouble(),
      currency: res['currency'] as String?,
      paymentStatus: OrderPaymentStatus.pending,
      logisticName: res['logisticName'] as String?,
      serviceFeeRate: (res['serviceFeeRate'] as num?)?.toDouble(),
      serviceFeeAmount: (res['serviceFeeAmount'] as num?)?.toDouble(),
      sellerRevenue: (res['sellerRevenue'] as num?)?.toDouble(),
    );
  }

  @override
  Future<List<OrderModel>> buyerOrders(String buyerId) async {
    final rows = await _db.orders
        .select()
        .eq('buyer_id', buyerId)
        .order('created_at', ascending: false);
    return _models(rows);
  }

  @override
  Future<List<OrderModel>> buyerStoreOrders(
      String buyerId, String storeId) async {
    final rows = await _db.orders
        .select()
        .eq('buyer_id', buyerId)
        .eq('store_id', storeId)
        .order('created_at', ascending: false);
    return _models(rows);
  }

  @override
  Future<List<OrderModel>> storeOrders(String storeId) async {
    final rows = await _db.orders
        .select()
        .eq('store_id', storeId)
        .order('created_at', ascending: false);
    return _models(rows);
  }

  @override
  Future<List<OrderModel>> sellerOrders(String sellerId) async {
    final rows = await _db.orders
        .select()
        .eq('seller_id', sellerId)
        .order('created_at', ascending: false);
    return _models(rows);
  }

  @override
  Future<List<OrderModel>> allOrders() async {
    final rows = await _db.orders
        .select()
        .order('created_at', ascending: false)
        .limit(200);
    return _models(rows);
  }

  /// `status`/`updated_at` are the only order columns a client may update
  /// (column-level grant in supabase/migrations).
  @override
  Future<void> updateStatus(String orderId, OrderStatus status) async {
    await _db.orders.update({
      'status': status.name,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', orderId);
  }

  List<OrderModel> _models(List<Map<String, dynamic>> rows) =>
      rows.map((r) => OrderModel.fromMap(fromRow(r))).toList();
}
