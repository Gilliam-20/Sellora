import 'package:get/get.dart';
import '../../../data/models/subscription_plan_model.dart';
import '../../../data/repositories/subscription_repository.dart';

class AdminPlansController extends GetxController {
  final SubscriptionRepository _subscriptionRepo =
      Get.find<SubscriptionRepository>();

  final plans = <SubscriptionPlanModel>[].obs;
  final isLoading = true.obs;
  final isSaving = false.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    plans.value = await _subscriptionRepo.fetchPlans();
    isLoading.value = false;
  }

  Future<void> updatePrice(SubscriptionPlanModel plan, double newPriceKes,
      double newPriceUsd) async {
    isSaving.value = true;
    try {
      final updated = SubscriptionPlanModel(
        id: plan.id,
        name: plan.name,
        priceUsd: newPriceUsd,
        priceKes: newPriceKes,
        billingPeriodDays: plan.billingPeriodDays,
        listingLimit: plan.listingLimit,
        commissionPercent: plan.commissionPercent,
        perks: plan.perks,
        isPopular: plan.isPopular,
      );
      await _subscriptionRepo.updatePlan(updated);
      await load();
    } finally {
      isSaving.value = false;
    }
  }
}
