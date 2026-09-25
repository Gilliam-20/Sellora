import '../models/billing_history_entry_model.dart';
import '../models/subscription_plan_model.dart';
import '../models/subscription_usage_model.dart';

abstract class SubscriptionRepository {
  Future<List<SubscriptionPlanModel>> fetchPlans();

  /// Starts a subscription purchase server-side: creates a pending
  /// billing_history ledger entry (plan price snapshotted, real server
  /// id) but does NOT activate anything. The caller uses the returned
  /// entry's id as the payment's reference — mirrors
  /// `SupabaseOrderRepository.placeOrder`'s create-then-pay pattern. Only a
  /// confirmed payment (the IntaSend webhook, or mock mode's synchronous
  /// activation) actually activates the subscription.
  Future<BillingHistoryEntryModel> subscribeSeller({
    required String sellerId,
    required String planId,
  });

  Future<void> updatePlan(SubscriptionPlanModel plan);

  /// Read-only usage against the seller's current plan limits, for the
  /// subscription screen.
  Future<SubscriptionUsageModel> fetchUsage(String sellerId);
}
