/// One completed refund, as `supabase/functions/_shared/refunds.js` appends
/// it to `orders.refunds`.
class RefundRecord {
  RefundRecord({
    required this.amount,
    required this.currency,
    this.provider,
    this.providerRefundId,
    this.reason,
    this.comment,
    this.createdAt,
  });

  final double amount;
  final String currency;
  final String? provider;
  final String? providerRefundId;
  final String? reason;
  final String? comment;
  final DateTime? createdAt;

  factory RefundRecord.fromMap(Map<String, dynamic> map) => RefundRecord(
        amount: (map['amount'] as num?)?.toDouble() ?? 0,
        currency: map['currency'] as String? ?? 'KES',
        provider: map['provider'] as String?,
        providerRefundId: map['providerRefundId'] as String?,
        reason: map['reason'] as String?,
        comment: map['comment'] as String?,
        createdAt:
            DateTime.tryParse(map['createdAt'] as String? ?? '')?.toLocal(),
      );
}

/// An order's refund state, read by admin from the `admin_order_refunds`
/// view (supabase/migrations/20261003000000_admin_order_refunds.sql) —
/// these are server-only `orders` columns nobody else can read.
///
/// The amounts are what the provider actually charged, not the order's
/// display total: IntaSend settles KES (`total_kes`) whatever currency the
/// shopper saw. [remaining]/[refusal] mirror `decideRefund` in
/// `_shared/refunds.js` so the sheet can explain a refusal before asking;
/// the server still makes the call.
class OrderRefundInfo {
  OrderRefundInfo({
    required this.orderId,
    this.paymentProvider,
    required this.paymentStatus,
    this.chargedAmount,
    this.refundedAmount = 0,
    this.refundStatus = 'NONE',
    this.refundError,
    this.refunds = const [],
    this.cjOrderStatus = 'NOT_PUSHED',
  });

  final String orderId;
  final String? paymentProvider;

  /// Raw `orders.payment_status` (including `awaiting_confirmation`).
  final String paymentStatus;

  /// What the provider charged, in [currency]. Null when the order never
  /// reached a provider.
  final double? chargedAmount;
  final double refundedAmount;

  /// `NONE`, `PROCESSING`, `REFUNDED` or `FAILED`.
  final String refundStatus;
  final String? refundError;
  final List<RefundRecord> refunds;

  /// `PUSHED` means CJ is already shipping it, so even a full refund leaves
  /// the order live (someone has to handle the return).
  final String cjOrderStatus;

  /// IntaSend is the only provider today and always settles KES.
  String get currency => 'KES';

  double get remaining {
    final charged = chargedAmount ?? 0;
    final left = ((charged - refundedAmount) * 100).round() / 100;
    return left < 0 ? 0 : left;
  }

  bool get shippedByCj => cjOrderStatus == 'PUSHED';

  /// Why this order can't be refunded right now, or null if it can. A
  /// `PROCESSING` refund may be a stale claim the server would take over,
  /// so that one is left to the server to decide.
  String? get refusal {
    const refundable = {'paid', 'partially_refunded', 'refunded'};
    if (!refundable.contains(paymentStatus)) {
      return 'This order was never paid, so there is nothing to refund.';
    }
    if (paymentProvider != 'INTASEND' || (chargedAmount ?? 0) <= 0) {
      return 'This order has no recorded charge to refund.';
    }
    if (remaining <= 0.01) {
      return 'This order has already been fully refunded.';
    }
    return null;
  }

  factory OrderRefundInfo.fromMap(Map<String, dynamic> map) => OrderRefundInfo(
        orderId: map['id'] as String,
        paymentProvider: map['paymentProvider'] as String?,
        paymentStatus: map['paymentStatus'] as String? ?? 'pending',
        chargedAmount: (map['totalKes'] as num?)?.toDouble(),
        refundedAmount: (map['refundedAmount'] as num?)?.toDouble() ?? 0,
        refundStatus: map['refundStatus'] as String? ?? 'NONE',
        refundError: map['refundError'] as String?,
        refunds: (map['refunds'] as List? ?? [])
            .map((e) => RefundRecord.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
        cjOrderStatus: map['cjOrderStatus'] as String? ?? 'NOT_PUSHED',
      );
}

/// The reasons IntaSend accepts (`REFUND_REASONS` in
/// `supabase/functions/_shared/intasendApi.js`); anything else is sent as
/// "Other".
const refundReasons = [
  'Requested by customer',
  'Unavailable',
  'Duplicate',
  'Fraudulent',
  'Other',
];
