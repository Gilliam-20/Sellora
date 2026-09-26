/// A seller's current subscription state, mirrored from `subscriptions/{sellerId}`.
///
/// Read-only from Dart — only the `intasendWebhook` Edge Function writes this
/// doc, on confirmed payment. There is no client write path and no producer
/// of a `cancelled` status yet; both are future work.
class SubscriptionRecordModel {
  SubscriptionRecordModel({
    required this.sellerId,
    required this.planId,
    required this.status,
    required this.orderLimit,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    required this.lastBillingHistoryId,
    this.updatedAt,
  });

  final String sellerId;
  final String planId;

  /// 'active' is the only status any Edge Function produces today.
  final String status;

  /// Snapshotted from the plan at confirmation time.
  final int orderLimit;
  final DateTime currentPeriodStart;
  final DateTime currentPeriodEnd;
  final String lastBillingHistoryId;
  final DateTime? updatedAt;

  factory SubscriptionRecordModel.fromMap(Map<String, dynamic> map) {
    return SubscriptionRecordModel(
      sellerId: map['sellerId'] as String,
      planId: map['planId'] as String,
      status: map['status'] as String? ?? 'active',
      orderLimit: map['orderLimit'] as int? ?? -1,
      currentPeriodStart:
          DateTime.tryParse(map['currentPeriodStart'] as String? ?? '') ??
              DateTime.now(),
      currentPeriodEnd:
          DateTime.tryParse(map['currentPeriodEnd'] as String? ?? '') ??
              DateTime.now(),
      lastBillingHistoryId: map['lastBillingHistoryId'] as String? ?? '',
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'] as String)
          : null,
    );
  }
}
