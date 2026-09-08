import '../models/subscription_plan_model.dart';

abstract class SubscriptionRepository {
  Future<List<SubscriptionPlanModel>> fetchPlans();
  Future<void> subscribeSeller({required String sellerId, required String planId, required String paymentReference});
  Future<void> updatePlan(SubscriptionPlanModel plan);
}
