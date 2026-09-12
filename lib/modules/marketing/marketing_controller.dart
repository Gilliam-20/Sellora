import 'package:get/get.dart';
import '../../data/models/subscription_plan_model.dart';
import '../../data/repositories/subscription_repository.dart';

/// Backs the public marketing/landing page. Only the pricing section
/// needs live data — everything else on the page is static copy.
class MarketingController extends GetxController {
  final SubscriptionRepository _subscriptionRepo =
      Get.find<SubscriptionRepository>();

  final plans = <SubscriptionPlanModel>[].obs;
  final isLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    try {
      plans.value = await _subscriptionRepo.fetchPlans();
    } catch (_) {
      // If plans can't load, the pricing section just renders empty —
      // the rest of the marketing page doesn't depend on it.
    } finally {
      isLoading.value = false;
    }
  }
}

class MarketingBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => MarketingController());
  }
}
