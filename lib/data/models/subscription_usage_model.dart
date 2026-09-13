/// Read-model for the seller subscription screen's usage display. Not
/// persisted — computed on demand from the seller's listing count and plan.
///
/// No order-count fields: order usage needs `sellerId` on `orders`, which
/// doesn't exist until the deferred multi-tenant order threading lands (see
/// WORKLOG.md, 2026-09-12).
class SubscriptionUsageModel {
  SubscriptionUsageModel({
    required this.listingCount,
    required this.listingLimit,
  });

  final int listingCount;

  /// -1 means unlimited.
  final int listingLimit;
}
