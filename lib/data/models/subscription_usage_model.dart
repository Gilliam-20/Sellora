/// Read-model for the seller's usage against their plan. Not persisted —
/// the server computes it (`my_plan_usage()`, supabase/migrations
/// 20260929000000_billing_usage.sql) the same way it enforces each limit,
/// so what the app shows is what publishing and checkout will allow.
class SubscriptionUsageModel {
  SubscriptionUsageModel({
    required this.listingCount,
    required this.listingLimit,
    this.orderCount = 0,
    this.orderLimit = -1,
    this.storeCount = 0,
    this.storeLimit = 1,
    this.subscriptionStatus = 'none',
    this.currentPeriodEnd,
    this.billingPeriodDays = 30,
  });

  /// Published listings across every store. Drafts are free.
  final int listingCount;

  /// -1 means unlimited, here and in the other limits.
  final int listingLimit;

  /// Paid orders over the rolling billing period, as checkout counts them.
  final int orderCount;
  final int orderLimit;
  final int storeCount;
  final int storeLimit;

  /// 'active' | 'lapsed' | 'cancelled' | 'none'.
  final String subscriptionStatus;
  final DateTime? currentPeriodEnd;

  /// The window [orderCount] covers.
  final int billingPeriodDays;

  bool get isActive => subscriptionStatus == 'active';

  factory SubscriptionUsageModel.fromMap(Map<String, dynamic> map) {
    int count(String key, int fallback) =>
        (map[key] as num?)?.toInt() ?? fallback;
    return SubscriptionUsageModel(
      listingCount: count('listingCount', 0),
      listingLimit: count('listingLimit', -1),
      orderCount: count('orderCount', 0),
      orderLimit: count('orderLimit', -1),
      storeCount: count('storeCount', 0),
      storeLimit: count('storeLimit', 1),
      subscriptionStatus: map['subscriptionStatus'] as String? ?? 'none',
      currentPeriodEnd:
          DateTime.tryParse(map['currentPeriodEnd'] as String? ?? '')
              ?.toLocal(),
      billingPeriodDays: count('billingPeriodDays', 30),
    );
  }
}
