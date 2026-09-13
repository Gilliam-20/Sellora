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
      await _subscriptionRepo
          .updatePlan(plan.copyWith(priceKes: newPriceKes, priceUsd: newPriceUsd));
      await load();
    } finally {
      isSaving.value = false;
    }
  }

  /// Schema-only fields — orderLimit/storeLimit aren't enforced anywhere
  /// yet (see WORKLOG.md, 2026-09-12), but stay admin-editable since the
  /// point is the config surface existing, not hiding it until enforcement
  /// lands.
  Future<void> updateLimitsAndFeatures(
    SubscriptionPlanModel plan, {
    int? orderLimit,
    int? storeLimit,
    Map<String, bool>? features,
  }) async {
    isSaving.value = true;
    try {
      await _subscriptionRepo.updatePlan(plan.copyWith(
        orderLimit: orderLimit,
        storeLimit: storeLimit,
        features: features,
      ));
      await load();
    } finally {
      isSaving.value = false;
    }
  }
}
