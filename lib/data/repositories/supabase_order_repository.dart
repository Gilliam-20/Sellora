import 'package:get/get.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/dio_client.dart';
import '../models/order_model.dart';
import '../services/supabase_service.dart';
import 'order_repository.dart';

class SupabaseOrderRepository extends GetxService implements OrderRepository {
  final SupabaseService _db = Get.find<SupabaseService>();
  final DioClient _dio = Get.find<DioClient>();

  /// Every column a client may read. `orders` also carries server-only
  /// bookkeeping (supplier cost, provider refs, CJ state), and a
  /// column-level grant refuses `select *` outright — so reads must name
  /// these. A column added here must be granted in a new migration too
  /// (see supabase/migrations/20260927000000_backend.sql).
  static const columns = 'id, code, buyer_id, seller_id, store_id, items, '
      'status, total, currency, shipping_address, payment_method, '
      'payment_reference, tracking_number, payment_status, service_fee_rate, '
      'service_fee_amount, seller_revenue, payment_fee, shipping_fee, '
      'logistic_name, created_at, updated_at, payment_provider, tracking, '
      'refunded_amount';

  @override
  Future<OrderModel> placeOrder(OrderModel order) async {
    // The order row is never written directly from the client — the
    // backend re-prices every item from CJ's own live price and the store's
    // own listed price itself, so a tampered `order.total`/fee field here is
    // simply ignored. See supabase/functions/_shared/orders.js's
    // createOrder, and the `orders` table having no insert policy.
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

    // The response is `{success, data: {id, code, totalAmount, currency,
    // serviceFeeRate, serviceFeeAmount, sellerRevenue, items, ...}}`. Its
    // `items` lack variantLabel, so this keeps the richer client-built list
    // rather than overwriting it — only the fields the server actually
    // recomputed are trusted here.
    final data = Map<String, dynamic>.from(res['data'] as Map);
    return order.copyWith(
      id: data['id'] as String,
      code: data['code'] as String? ?? data['id'] as String,
      total: (data['totalAmount'] as num).toDouble(),
      currency: data['currency'] as String?,
      paymentStatus: OrderPaymentStatus.pending,
      logisticName: data['logisticName'] as String?,
      serviceFeeRate: (data['serviceFeeRate'] as num?)?.toDouble(),
      serviceFeeAmount: (data['serviceFeeAmount'] as num?)?.toDouble(),
      sellerRevenue: (data['sellerRevenue'] as num?)?.toDouble(),
    );
  }

  @override
  Future<List<OrderModel>> buyerOrders(String buyerId) async {
    final rows = await _db.orders
        .select(columns)
        .eq('buyer_id', buyerId)
        .order('created_at', ascending: false);
    return _models(rows);
  }

  @override
  Future<List<OrderModel>> buyerStoreOrders(
      String buyerId, String storeId) async {
    final rows = await _db.orders
        .select(columns)
        .eq('buyer_id', buyerId)
        .eq('store_id', storeId)
        .order('created_at', ascending: false);
    return _models(rows);
  }

  @override
  Future<List<OrderModel>> storeOrders(String storeId) async {
    final rows = await _db.orders
        .select(columns)
        .eq('store_id', storeId)
        .order('created_at', ascending: false);
    return _models(rows);
  }

  @override
  Future<List<OrderModel>> sellerOrders(String sellerId) async {
    final rows = await _db.orders
        .select(columns)
        .eq('seller_id', sellerId)
        .order('created_at', ascending: false);
    return _models(rows);
  }

  @override
  Future<List<OrderModel>> allOrders() async {
    final rows = await _db.orders
        .select(columns)
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
