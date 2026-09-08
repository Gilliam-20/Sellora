import 'package:get/get.dart';
import '../../mock/mock_seed_data.dart';
import '../../models/subscription_plan_model.dart';
import '../subscription_repository.dart';

class MockSubscriptionRepository extends GetxService implements SubscriptionRepository {
  final List<SubscriptionPlanModel> _plans = MockSeedData.plans();

  @override
  Future<List<SubscriptionPlanModel>> fetchPlans() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _plans;
  }

  @override
  Future<void> subscribeSeller({required String sellerId, required String planId, required String paymentReference}) async {
    await Future.delayed(const Duration(milliseconds: 500));
    // In mock mode this is a no-op beyond the delay — AuthController
    // updates the cached mock user's plan directly after this resolves.
  }

  @override
  Future<void> updatePlan(SubscriptionPlanModel plan) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final index = _plans.indexWhere((p) => p.id == plan.id);
    if (index != -1) _plans[index] = plan;
  }
}
