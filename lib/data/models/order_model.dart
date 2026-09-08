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
  });

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
      };
}
