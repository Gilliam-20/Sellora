import '../models/billing_history_entry_model.dart';
import '../models/billing_profile_model.dart';
import '../models/subscription_plan_model.dart';
import '../models/subscription_usage_model.dart';

/// [SubscriptionRepository.createPlan] was given an id another plan has.
class PlanIdTaken implements Exception {
  const PlanIdTaken(this.id);
  final String id;

  @override
  String toString() => 'A plan with the ID "$id" already exists';
}

abstract class SubscriptionRepository {
  /// Every plan, retired ones included, in display order
  /// (`SubscriptionPlanModel.sorted`). Seller-facing lists narrow it with
  /// `SubscriptionPlanModel.offered`.
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

  /// Adds a plan (admin only). Throws [PlanIdTaken] rather than overwriting
  /// an existing plan with the same id.
  Future<void> createPlan(SubscriptionPlanModel plan);

  /// Read-only usage against the seller's current plan limits, counted the
  /// way the server enforces them.
  Future<SubscriptionUsageModel> fetchUsage(String sellerId);

  /// The seller's subscription payments, newest first — pending and failed
  /// attempts included, since those are what a seller asks support about.
  Future<List<BillingHistoryEntryModel>> billingHistory(String sellerId,
      {int limit = 24});

  /// Marks the signed-in seller's running plan to end at its period end:
  /// it keeps working until then, and renewal reminders stop. There's no
  /// automatic charge to stop, so this is the seller saying they won't
  /// renew. Paying for another period clears it.
  Future<void> cancelSubscription({String? reason});

  /// Undoes [cancelSubscription] while the period is still running.
  Future<void> resumeSubscription();

  /// The seller's saved payment method and invoice details, or null if
  /// they've never saved any.
  Future<BillingProfileModel?> fetchBillingProfile(String sellerId);

  Future<void> saveBillingProfile(BillingProfileModel profile);
}
