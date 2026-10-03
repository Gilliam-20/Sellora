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
/// IntaSend webhook (see supabase/functions/api/index.ts). Named distinctly
/// from IntasendService's own `PaymentStatus` (a single collection call's
/// immediate result) to avoid an import collision — this one is the
/// order's persisted state, written only by the backend.
enum OrderPaymentStatus { pending, paid, failed, partiallyRefunded, refunded }

extension OrderPaymentStatusX on OrderPaymentStatus {
  String get label => switch (this) {
        OrderPaymentStatus.pending => 'Pending',
        OrderPaymentStatus.paid => 'Paid',
        OrderPaymentStatus.failed => 'Failed',
        OrderPaymentStatus.partiallyRefunded => 'Partially refunded',
        OrderPaymentStatus.refunded => 'Refunded',
      };

  /// Parses the `orders.payment_status` column. `awaiting_confirmation`
  /// (a payment prompt is out, not yet confirmed) reads as [pending], and
  /// so does anything unrecognised.
  static OrderPaymentStatus parse(Object? value) => switch (value) {
        'paid' => OrderPaymentStatus.paid,
        'failed' => OrderPaymentStatus.failed,
        'partially_refunded' => OrderPaymentStatus.partiallyRefunded,
        'refunded' => OrderPaymentStatus.refunded,
        _ => OrderPaymentStatus.pending,
      };
}

/// Where an order ships, in the shape CJ fulfilment needs
/// (`createDropshipOrder` in `supabase/functions/_shared/cjApi.js`).
/// `createOrder` refuses an order missing [fullName], [phone], [line1] or
/// [city] (`normalizeShippingAddress` in `_shared/orders.js`), and derives
/// the order's region/currency from [countryCode].
class ShippingAddress {
  ShippingAddress({
    required this.countryCode,
    this.fullName = '',
    this.phone = '',
    this.email,
    this.line1 = '',
    this.line2,
    this.city = '',
    this.province,
    this.zip,
  });

  final String countryCode;
  final String fullName;
  final String phone;
  final String? email;
  final String line1;
  final String? line2;
  final String city;
  final String? province;
  final String? zip;

  /// One line for receipts and order lists.
  String get summary => [line1, line2, city, province, zip, countryCode]
      .where((part) => part != null && part.isNotEmpty)
      .join(', ');

  Map<String, dynamic> toMap() => {
        'countryCode': countryCode,
        'fullName': fullName,
        'phone': phone,
        if (email != null && email!.isNotEmpty) 'email': email,
        'line1': line1,
        if (line2 != null && line2!.isNotEmpty) 'line2': line2,
        'city': city,
        if (province != null && province!.isNotEmpty) 'province': province,
        if (zip != null && zip!.isNotEmpty) 'zip': zip,
      };

  /// Also reads the `{countryCode, line}` shape stored before addresses
  /// were structured, as [line1].
  factory ShippingAddress.fromMap(Map<String, dynamic> map) => ShippingAddress(
        countryCode: map['countryCode'] as String? ?? '',
        fullName: map['fullName'] as String? ?? '',
        phone: map['phone'] as String? ?? '',
        email: map['email'] as String?,
        line1: map['line1'] as String? ?? map['line'] as String? ?? '',
        line2: map['line2'] as String?,
        city: map['city'] as String? ?? '',
        province: map['province'] as String?,
        zip: map['zip'] as String?,
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
  /// `{pid, vid, quantity}` line-item shape needs (supabase/functions/_shared/orders.js).
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
    this.discountCode,
    this.discountAmount = 0,
    this.serviceFeeBase = 'subtotal',
    this.refundedAmount = 0,
    this.tracking,
    this.cjOrderStatus,
    this.cjOrderNumber,
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
    String? discountCode,
    double? discountAmount,
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
      discountCode: discountCode ?? this.discountCode,
      discountAmount: discountAmount ?? this.discountAmount,
      serviceFeeBase: serviceFeeBase,
      refundedAmount: refundedAmount,
      tracking: tracking,
      cjOrderStatus: cjOrderStatus,
      cjOrderNumber: cjOrderNumber,
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
  /// supabase/functions/api/index.ts's webhook, never by the client).
  final OrderPaymentStatus paymentStatus;

  // ---- Fee snapshot ---------------------------------------------------
  // Computed once, server-side, at order-creation time (see
  // supabase/functions/_shared/orders.js createOrder) and never recomputed — changing
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
  /// `createOrder` auto-picked as cheapest (see supabase/functions/_shared/orders.js).
  /// Also what `fulfillOrder` tells CJ to use when pushing the order.
  final String? logisticName;

  /// The discount code the buyer used, if any, and what it took off the
  /// goods, in [currency]. Priced server-side by `createOrder` and already
  /// subtracted from [total].
  final String? discountCode;
  final double discountAmount;

  /// What [serviceFeeAmount] was charged on: `subtotal` (the goods, the
  /// default) or `subtotal_and_shipping`, when an admin had configured the
  /// fee to take shipping too. Snapshotted with the rate.
  final String serviceFeeBase;

  /// How much has been refunded to the buyer so far, in [currency].
  final double refundedAmount;

  /// The latest shipment snapshot from CJ and the carrier, or null before
  /// the order ships.
  final OrderTracking? tracking;

  /// CJ's side of fulfilment (`NOT_PUSHED`, `PUSHING`, `PUSHED`, `FAILED`,
  /// `NEEDS_RECONCILIATION`) and CJ's own order number. Only on the seller's
  /// and admin's read (`seller_orders`); null for a buyer.
  final String? cjOrderStatus;
  final String? cjOrderNumber;

  /// The seller's goods subtotal, before any discount: what the line items
  /// add up to.
  double get itemsSubtotal => items.fold(0, (sum, item) => sum + item.total);

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

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
          : ShippingAddress(countryCode: ''),
      paymentMethod: map['paymentMethod'] as String? ?? 'IntaSend',
      paymentReference: map['paymentReference'] as String?,
      trackingNumber: map['trackingNumber'] as String?,
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
      paymentStatus: OrderPaymentStatusX.parse(map['paymentStatus']),
      serviceFeeRate: (map['serviceFeeRate'] as num?)?.toDouble() ?? 0,
      serviceFeeAmount: (map['serviceFeeAmount'] as num?)?.toDouble() ?? 0,
      sellerRevenue: (map['sellerRevenue'] as num?)?.toDouble() ?? 0,
      paymentFee: (map['paymentFee'] as num?)?.toDouble() ?? 0,
      shippingFee: (map['shippingFee'] as num?)?.toDouble() ?? 0,
      logisticName: map['logisticName'] as String?,
      discountCode: map['discountCode'] as String?,
      discountAmount: (map['discountAmount'] as num?)?.toDouble() ?? 0,
      serviceFeeBase: map['serviceFeeBase'] as String? ?? 'subtotal',
      refundedAmount: (map['refundedAmount'] as num?)?.toDouble() ?? 0,
      tracking: map['tracking'] is Map
          ? OrderTracking.fromMap(
              Map<String, dynamic>.from(map['tracking'] as Map))
          : null,
      cjOrderStatus: map['cjOrderStatus'] as String?,
      cjOrderNumber: map['cjOrderNumber'] as String?,
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
        'discountCode': discountCode,
        'discountAmount': discountAmount,
        'serviceFeeBase': serviceFeeBase,
        'refundedAmount': refundedAmount,
      };
}

/// The `orders.tracking` snapshot `buildTracking` writes
/// (supabase/functions/_shared/tracking.js). Every field is optional: CJ's
/// response shapes aren't confirmed against a real account yet.
class OrderTracking {
  OrderTracking({
    this.status,
    this.trackingNumber,
    this.trackingUrl,
    this.carrier,
    this.events = const [],
  });

  /// One of tracking.js's `SHIPMENT` values, e.g. `IN_TRANSIT`.
  final String? status;
  final String? trackingNumber;
  final String? trackingUrl;
  final String? carrier;

  /// Newest first, as tracking.js sorts them.
  final List<TrackingEvent> events;

  String get statusLabel => switch (status) {
        'PENDING' => 'With CJ, not yet shipped',
        'IN_TRANSIT' => 'In transit',
        'OUT_FOR_DELIVERY' => 'Out for delivery',
        'DELIVERED' => 'Delivered',
        'EXCEPTION' => 'Carrier reported a problem',
        'CANCELLED' => 'Cancelled',
        _ => 'Unknown',
      };

  factory OrderTracking.fromMap(Map<String, dynamic> map) => OrderTracking(
        status: map['status'] as String?,
        trackingNumber: map['trackingNumber'] as String?,
        trackingUrl: map['trackingUrl'] as String?,
        carrier: map['carrier'] as String?,
        events: (map['events'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => TrackingEvent.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class TrackingEvent {
  TrackingEvent({this.at, this.description = '', this.location});

  /// As the carrier gave it; not always a parseable date.
  final String? at;
  final String description;
  final String? location;

  factory TrackingEvent.fromMap(Map<String, dynamic> map) => TrackingEvent(
        at: map['at'] as String?,
        description: map['description'] as String? ?? '',
        location: map['location'] as String?,
      );
}
