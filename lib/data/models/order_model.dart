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

/// Where an order ships. `countryCode` is the only field
/// `functions/lib/orders.js`'s `createOrder` validates — it derives the
/// order's region/currency from it (see `functions/lib/regions.js`) and
/// rejects a request without one. `line` is the free-text street/city
/// address collected before this class existed.
///
/// NOT yet the full `{fullName, phone, email, line1, line2, city, province,
/// zip}` shape `functions/lib/cjApi.js` needs to actually push a fulfillment
/// to CJ — that's a separate, still-open gap (see WORKLOG.md 2026-09-15).
class ShippingAddress {
  ShippingAddress({required this.countryCode, required this.line});

  final String countryCode;
  final String line;

  Map<String, dynamic> toMap() => {'countryCode': countryCode, 'line': line};

  factory ShippingAddress.fromMap(Map<String, dynamic> map) => ShippingAddress(
        countryCode: map['countryCode'] as String? ?? '',
        line: map['line'] as String? ?? '',
      );
}

class OrderItem {
  OrderItem({
    required this.productId,
    this.cjProductId,
    required this.title,
    required this.imageUrl,
    required this.quantity,
    required this.unitPrice,
    this.variantId,
    this.variantLabel,
  });

  final String productId;

  /// CJ's own product id (`pid`) — the value `createOrder`'s
  /// `{pid, vid, quantity}` line-item shape needs (functions/lib/orders.js).
  /// Null for a listing with no CJ origin.
  final String? cjProductId;
  final String title;
  final String imageUrl;
  final int quantity;
  final double unitPrice;

  /// CJ's own purchasable per-SKU id (`vid`) for the chosen [ProductVariant].
  /// Required by `createOrder` alongside [cjProductId]; null when the
  /// product has no real CJ variant data.
  final String? variantId;

  /// Human-readable variant label for display/receipts (e.g. "Black / M") —
  /// see [ProductVariant.label].
  final String? variantLabel;

  double get total => unitPrice * quantity;

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'cjProductId': cjProductId,
        'title': title,
        'imageUrl': imageUrl,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'variantId': variantId,
        'variantLabel': variantLabel,
      };

  factory OrderItem.fromMap(Map<String, dynamic> map) => OrderItem(
        productId: map['productId'] as String,
        cjProductId: map['cjProductId'] as String?,
        title: map['title'] as String,
        imageUrl: map['imageUrl'] as String? ?? '',
        quantity: map['quantity'] as int? ?? 1,
        unitPrice: (map['unitPrice'] as num?)?.toDouble() ?? 0,
        variantId: map['variantId'] as String?,
        variantLabel: map['variantLabel'] as String?,
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
    this.shippingFee = 0,
    this.logisticName,
  });

  OrderModel copyWith({
    String? id,
    String? code,
    double? total,
    String? currency,
    String? paymentReference,
    OrderStatus? status,
    OrderPaymentStatus? paymentStatus,
    double? serviceFeeRate,
    double? serviceFeeAmount,
    double? sellerRevenue,
    String? logisticName,
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
      currency: currency ?? this.currency,
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
      shippingFee: shippingFee,
      logisticName: logisticName ?? this.logisticName,
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
  final ShippingAddress shippingAddress;
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

  /// Shipping portion of [total], snapshotted at order-creation time the
  /// same way the fee fields above are — a later change to how shipping is
  /// priced must not alter historical orders.
  final double shippingFee;

  /// The CJ shipping line this order ships on (e.g. "CJPacket Ordinary") —
  /// either the buyer's checkout pick or, if none was sent, whatever
  /// `createOrder` auto-picked as cheapest (see functions/lib/orders.js).
  /// Also what `fulfillOrder` tells CJ to use when pushing the order.
  final String? logisticName;

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
      shippingAddress: map['shippingAddress'] is Map
          ? ShippingAddress.fromMap(
              Map<String, dynamic>.from(map['shippingAddress'] as Map))
          : ShippingAddress(countryCode: '', line: ''),
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
      shippingFee: (map['shippingFee'] as num?)?.toDouble() ?? 0,
      logisticName: map['logisticName'] as String?,
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
        'shippingAddress': shippingAddress.toMap(),
        'paymentMethod': paymentMethod,
        'paymentReference': paymentReference,
        'trackingNumber': trackingNumber,
        'createdAt': createdAt.toIso8601String(),
        'paymentStatus': paymentStatus.name,
        'serviceFeeRate': serviceFeeRate,
        'serviceFeeAmount': serviceFeeAmount,
        'sellerRevenue': sellerRevenue,
        'paymentFee': paymentFee,
        'shippingFee': shippingFee,
        'logisticName': logisticName,
      };
}
