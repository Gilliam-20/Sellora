enum OrderStatus { pending, processing, shipped, delivered, cancelled }

extension OrderStatusX on OrderStatus {
  String get label => switch (this) {
        OrderStatus.pending => 'Pending',
        OrderStatus.processing => 'Processing',
        OrderStatus.shipped => 'Shipped',
        OrderStatus.delivered => 'Delivered',
        OrderStatus.cancelled => 'Cancelled',
      };
}

/// Whether the buyer's payment has actually cleared — separate from
/// [OrderStatus], which tracks fulfillment. An order can be `pending`
/// fulfillment while its payment is still `pending` confirmation from the
/// IntaSend webhook (see functions/src/intasend.ts). Named distinctly from
/// IntasendService's own `PaymentStatus` (a single collection call's
/// immediate result) to avoid an import collision — this one is the
/// order's persisted state.
enum OrderPaymentStatus { pending, paid, failed }

extension OrderPaymentStatusX on OrderPaymentStatus {
  String get label => switch (this) {
        OrderPaymentStatus.pending => 'Pending',
        OrderPaymentStatus.paid => 'Paid',
        OrderPaymentStatus.failed => 'Failed',
      };
}

class OrderItem {
  OrderItem({
    required this.productId,
    required this.title,
    required this.imageUrl,
    required this.quantity,
    required this.unitPrice,
    this.variant,
  });

  final String productId;
  final String title;
  final String imageUrl;
  final int quantity;
  final double unitPrice;
  final String? variant;

  double get total => unitPrice * quantity;

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'title': title,
        'imageUrl': imageUrl,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'variant': variant,
      };

  factory OrderItem.fromMap(Map<String, dynamic> map) => OrderItem(
        productId: map['productId'] as String,
        title: map['title'] as String,
        imageUrl: map['imageUrl'] as String? ?? '',
        quantity: map['quantity'] as int? ?? 1,
        unitPrice: (map['unitPrice'] as num?)?.toDouble() ?? 0,
        variant: map['variant'] as String?,
      );
}

/// A buyer order. `sellerId` ties it back to the seller who listed the
/// product for their dashboard/earnings view; fulfillment itself is
/// placed with CJ Dropshipping via the sellerId's linked catalog entry.
class OrderModel {
  OrderModel({
    required this.id,
    required this.code,
    required this.buyerId,
    required this.sellerId,
    this.storeId,
    required this.items,
    required this.status,
    required this.total,
    this.currency = 'USD',
    required this.shippingAddress,
    this.paymentMethod = 'IntaSend',
    this.paymentReference,
    this.trackingNumber,
    required this.createdAt,
    this.paymentStatus = OrderPaymentStatus.pending,
    this.serviceFeeRate = 0,
    this.serviceFeeAmount = 0,
    this.sellerRevenue = 0,
    this.paymentFee = 0,
  });

  OrderModel copyWith({
    String? id,
    String? code,
    double? total,
    String? paymentReference,
    OrderStatus? status,
    OrderPaymentStatus? paymentStatus,
    double? serviceFeeRate,
    double? serviceFeeAmount,
    double? sellerRevenue,
  }) {
    return OrderModel(
      id: id ?? this.id,
      code: code ?? this.code,
      buyerId: buyerId,
      sellerId: sellerId,
      storeId: storeId,
      items: items,
      status: status ?? this.status,
      total: total ?? this.total,
      currency: currency,
      shippingAddress: shippingAddress,
      paymentMethod: paymentMethod,
      paymentReference: paymentReference ?? this.paymentReference,
      trackingNumber: trackingNumber,
      createdAt: createdAt,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      serviceFeeRate: serviceFeeRate ?? this.serviceFeeRate,
      serviceFeeAmount: serviceFeeAmount ?? this.serviceFeeAmount,
      sellerRevenue: sellerRevenue ?? this.sellerRevenue,
      paymentFee: paymentFee,
    );
  }

  final String id;
  final String code; // human-readable manifest code, e.g. SLR-2049
  final String buyerId;
  final String sellerId;

  /// The store (see StoreModel) this order was placed against. Nullable
  /// for orders placed before stores existed; new orders always set it.
  final String? storeId;
  final List<OrderItem> items;
  final OrderStatus status;
  final double total;
  final String currency;
  final String shippingAddress;
  final String paymentMethod;
  final String? paymentReference;
  final String? trackingNumber;
  final DateTime createdAt;

  /// Whether the buyer's payment has actually cleared (set by
  /// functions/src/intasend.ts's webhook, never by the client).
  final OrderPaymentStatus paymentStatus;

  // ---- Fee snapshot ---------------------------------------------------
  // Computed once, server-side, at order-creation time (see
  // functions/src/orders.ts createOrder) and never recomputed — changing
  // AppConstants.platformServiceFeeRate later must not alter historical
  // orders.
  final double serviceFeeRate;
  final double serviceFeeAmount;
  final double sellerRevenue;
  final double paymentFee;

  factory OrderModel.fromMap(Map<String, dynamic> map) {
    return OrderModel(
      id: map['id'] as String,
      code: map['code'] as String? ?? '',
      buyerId: map['buyerId'] as String,
      sellerId: map['sellerId'] as String,
      storeId: map['storeId'] as String?,
      items: (map['items'] as List? ?? [])
          .map((e) => OrderItem.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      status: OrderStatus.values.firstWhere((s) => s.name == map['status'],
          orElse: () => OrderStatus.pending),
      total: (map['total'] as num?)?.toDouble() ?? 0,
      currency: map['currency'] as String? ?? 'USD',
      shippingAddress: map['shippingAddress'] as String? ?? '',
      paymentMethod: map['paymentMethod'] as String? ?? 'IntaSend',
      paymentReference: map['paymentReference'] as String?,
      trackingNumber: map['trackingNumber'] as String?,
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
      paymentStatus: OrderPaymentStatus.values.firstWhere(
          (s) => s.name == map['paymentStatus'],
          orElse: () => OrderPaymentStatus.pending),
      serviceFeeRate: (map['serviceFeeRate'] as num?)?.toDouble() ?? 0,
      serviceFeeAmount: (map['serviceFeeAmount'] as num?)?.toDouble() ?? 0,
      sellerRevenue: (map['sellerRevenue'] as num?)?.toDouble() ?? 0,
      paymentFee: (map['paymentFee'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'code': code,
        'buyerId': buyerId,
        'sellerId': sellerId,
        'storeId': storeId,
        'items': items.map((e) => e.toMap()).toList(),
        'status': status.name,
        'total': total,
        'currency': currency,
        'shippingAddress': shippingAddress,
        'paymentMethod': paymentMethod,
        'paymentReference': paymentReference,
        'trackingNumber': trackingNumber,
        'createdAt': createdAt.toIso8601String(),
        'paymentStatus': paymentStatus.name,
        'serviceFeeRate': serviceFeeRate,
        'serviceFeeAmount': serviceFeeAmount,
        'sellerRevenue': sellerRevenue,
        'paymentFee': paymentFee,
      };
}
