/// An append-only ledger entry for a seller's subscription payment, mirrored
/// from `billing_history/{id}`. The doc id doubles as the payment provider's
/// `api_ref`/reference — see `functions/lib/subscriptions.js`.
///
/// Every field but `status`/`paymentReference`/`paidAt` is snapshotted at
/// creation time and never rewritten, even if an admin edits the plan's
/// price later — the same "never modify historical fees" precedent
/// `OrderModel`'s fee fields already follow.
class BillingHistoryEntryModel {
  BillingHistoryEntryModel({
    required this.id,
    required this.sellerId,
    required this.planId,
    required this.planName,
    required this.amountKes,
    required this.amountUsd,
    required this.billingPeriodDays,
    required this.status,
    required this.paymentProvider,
    this.paymentReference,
    required this.createdAt,
    this.paidAt,
  });

  final String id;
  final String sellerId;
  final String planId;
  final String planName;
  final double amountKes;
  final double amountUsd;
  final int billingPeriodDays;

  /// 'pending' | 'paid' | 'failed'
  final String status;
  final String paymentProvider;
  final String? paymentReference;
  final DateTime createdAt;
  final DateTime? paidAt;

  factory BillingHistoryEntryModel.fromMap(Map<String, dynamic> map) {
    return BillingHistoryEntryModel(
      id: map['id'] as String,
      sellerId: map['sellerId'] as String,
      planId: map['planId'] as String,
      planName: map['planName'] as String? ?? '',
      amountKes: (map['amountKes'] as num?)?.toDouble() ?? 0,
      amountUsd: (map['amountUsd'] as num?)?.toDouble() ?? 0,
      billingPeriodDays: map['billingPeriodDays'] as int? ?? 30,
      status: map['status'] as String? ?? 'pending',
      paymentProvider: map['paymentProvider'] as String? ?? 'INTASEND',
      paymentReference: map['paymentReference'] as String?,
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
      paidAt: map['paidAt'] != null
          ? DateTime.tryParse(map['paidAt'] as String)
          : null,
    );
  }
}
