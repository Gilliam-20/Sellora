import '../../../data/models/order_model.dart';

/// The seller's order-list filters (TODO.md §14). No "partially fulfilled":
/// a CJ order ships as one parcel, so there are no partial shipments to
/// filter on. Partial refunds count under [refunded].
enum OrderFilter {
  all('All'),
  unpaid('Unpaid'),
  paid('Paid'),
  pending('Pending'),
  processing('Processing'),
  fulfilled('Fulfilled'),
  cancelled('Cancelled'),
  refunded('Refunded');

  const OrderFilter(this.label);
  final String label;

  bool matches(OrderModel order) => switch (this) {
        OrderFilter.all => true,
        OrderFilter.unpaid => order.status != OrderStatus.cancelled &&
            (order.paymentStatus == OrderPaymentStatus.pending ||
                order.paymentStatus == OrderPaymentStatus.failed),
        OrderFilter.paid => order.paymentStatus == OrderPaymentStatus.paid,
        OrderFilter.pending => order.status == OrderStatus.pending,
        OrderFilter.processing => order.status == OrderStatus.processing,
        OrderFilter.fulfilled => order.status == OrderStatus.shipped ||
            order.status == OrderStatus.delivered,
        OrderFilter.cancelled => order.status == OrderStatus.cancelled,
        OrderFilter.refunded =>
          order.paymentStatus == OrderPaymentStatus.refunded ||
              order.paymentStatus == OrderPaymentStatus.partiallyRefunded,
      };
}

/// Display helpers shared by the order list and detail.
extension SellerOrderView on OrderModel {
  /// Who placed it: the name on the shipping address.
  String get customerName {
    final name = shippingAddress.fullName.trim();
    return name.isEmpty ? 'Customer' : name;
  }

  /// Every storefront order comes through the seller's own online store;
  /// there are no other sales channels yet.
  String get channelLabel => 'Online store';

  /// Fulfilment as the seller cares about it, folding in CJ's side.
  String get fulfillmentLabel {
    switch (status) {
      case OrderStatus.cancelled:
        return 'Cancelled';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.shipped:
        return 'Shipped';
      case OrderStatus.pending:
        return 'Unfulfilled';
      case OrderStatus.processing:
        return switch (cjOrderStatus) {
          'PUSHED' => 'With CJ',
          'PUSHING' => 'Sending to CJ',
          'FAILED' => 'CJ retrying',
          'NEEDS_RECONCILIATION' => 'On hold',
          _ => 'Unfulfilled',
        };
    }
  }

  /// CJ's side alone, for the detail screen.
  String get cjStatusLabel => switch (cjOrderStatus) {
        'PUSHED' =>
          'Placed with CJ${cjOrderNumber == null ? '' : ' (#$cjOrderNumber)'}',
        'PUSHING' => 'Being sent to CJ',
        'FAILED' => 'CJ didn\'t accept it yet; Sellora retries automatically',
        'NEEDS_RECONCILIATION' => 'Held for review by Sellora',
        'NOT_PUSHED' || null => paymentStatus == OrderPaymentStatus.paid
            ? 'Not sent to CJ yet'
            : 'Sent to CJ once paid',
        _ => cjOrderStatus!,
      };

  /// Whether the seller may cancel it: only before anyone has paid, and not
  /// with a payment in flight (the `orders_guard_status` trigger's rule;
  /// the app can't tell `awaiting_confirmation` from `pending`, so the
  /// server has the last word).
  bool get sellerCanCancel =>
      status == OrderStatus.pending &&
      (paymentStatus == OrderPaymentStatus.pending ||
          paymentStatus == OrderPaymentStatus.failed);

  /// Free-text match on the order code, customer name, email and phone.
  bool matchesQuery(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      code,
      shippingAddress.fullName,
      shippingAddress.email ?? '',
      shippingAddress.phone,
    ].any((field) => field.toLowerCase().contains(q));
  }
}
