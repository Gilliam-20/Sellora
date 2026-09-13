import 'package:get/get.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/subscription_plan_model.dart';
import '../../../data/models/subscription_usage_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/subscription_repository.dart';
import '../../../data/services/intasend_service.dart';

class SellerSubscriptionController extends GetxController {
  final SubscriptionRepository _subscriptionRepo =
      Get.find<SubscriptionRepository>();
  final AuthRepository authRepo = Get.find<AuthRepository>();

  final plans = <SubscriptionPlanModel>[].obs;
  final usage = Rxn<SubscriptionUsageModel>();
  final isLoading = true.obs;
  final isPaying = false.obs;
  final isRefreshing = false.obs;
  final errorMessage = RxnString();

  SubscriptionPlanModel? get currentPlan => plans
      .firstWhereOrNull((p) => p.id == authRepo.cachedUser?.subscriptionPlanId);

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    plans.value = await _subscriptionRepo.fetchPlans();
    final uid = authRepo.cachedUser?.uid;
    if (uid != null) {
      usage.value = await _subscriptionRepo.fetchUsage(uid);
    }
    isLoading.value = false;
  }

  Future<void> switchPlan(SubscriptionPlanModel plan, String mpesaPhone) async {
    final user = authRepo.cachedUser;
    if (user == null) return;
    isPaying.value = true;
    errorMessage.value = null;
    try {
      final entry = await _subscriptionRepo.subscribeSeller(
          sellerId: user.uid, planId: plan.id);

      if (AppConstants.useMockData) {
        // Mock mode's repository already activated the switch synchronously.
        Get.back();
        Get.snackbar('Plan updated', 'You\'re now on the ${plan.name} plan.');
        await load();
        return;
      }

      await Get.find<IntasendService>().payBillingMpesa(
        billingEntryId: entry.id,
        phone: Formatters.toMpesaFormat(mpesaPhone),
      );
      // No live confirmation channel — same fire-and-forget pattern as
      // onboarding and buyer checkout. refreshStatus() is the recovery path.
      Get.back();
      Get.snackbar('Almost there',
          'Complete the M-Pesa prompt on your phone, then tap "Refresh status" below.');
    } catch (e) {
      errorMessage.value =
          'Payment didn\'t go through. Check the number and try again.';
    } finally {
      isPaying.value = false;
    }
  }

  /// Re-reads the signed-in user's Firestore doc (bypassing the in-memory
  /// cache) in case the webhook has activated a plan switch since this
  /// screen was opened, then reloads usage against whatever plan is
  /// current now.
  Future<void> refreshStatus() async {
    isRefreshing.value = true;
    try {
      await authRepo.refreshCurrentUser();
      await load();
    } finally {
      isRefreshing.value = false;
    }
  }
}
