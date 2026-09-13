import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/subscription_plan_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/subscription_repository.dart';
import '../../../data/services/intasend_service.dart';

enum OnboardingStep { choosePlan, pay, pendingConfirmation }

class SellerOnboardingController extends GetxController {
  final SubscriptionRepository _subscriptionRepo =
      Get.find<SubscriptionRepository>();
  final AuthRepository _authRepo = Get.find<AuthRepository>();

  final plans = <SubscriptionPlanModel>[].obs;
  final selectedPlanId = RxnString();
  final step = OnboardingStep.choosePlan.obs;
  final isLoadingPlans = true.obs;
  final isPaying = false.obs;
  final isRefreshing = false.obs;
  final errorMessage = RxnString();

  SubscriptionPlanModel? get selectedPlan =>
      plans.firstWhereOrNull((p) => p.id == selectedPlanId.value);

  @override
  void onInit() {
    super.onInit();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    isLoadingPlans.value = true;
    plans.value = await _subscriptionRepo.fetchPlans();
    selectedPlanId.value =
        plans.firstWhereOrNull((p) => p.isPopular)?.id ?? plans.first.id;
    isLoadingPlans.value = false;
  }

  void selectPlan(String planId) => selectedPlanId.value = planId;

  void goToPayment() => step.value = OnboardingStep.pay;

  Future<void> payWithMpesa(String phone) async {
    final plan = selectedPlan;
    final user = _authRepo.cachedUser;
    if (plan == null || user == null) return;

    isPaying.value = true;
    errorMessage.value = null;
    try {
      final entry = await _subscriptionRepo.subscribeSeller(
          sellerId: user.uid, planId: plan.id);

      if (AppConstants.useMockData) {
        // Mock mode's repository already activated the subscription
        // synchronously — nothing left to wait on.
        Get.offAllNamed(Routes.sellerShell);
        Get.snackbar('You\'re live',
            'Your ${plan.name} subscription is active — start listing products.');
        return;
      }

      await Get.find<IntasendService>().payBillingMpesa(
        billingEntryId: entry.id,
        phone: Formatters.toMpesaFormat(phone),
      );
      // No live confirmation channel — the IntaSend webhook activates the
      // subscription asynchronously (matching buyer checkout's own
      // fire-and-forget pattern). Show the pending step; refreshStatus()
      // is the manual recovery path once the customer has paid.
      step.value = OnboardingStep.pendingConfirmation;
      Get.snackbar('Almost there',
          'Complete the M-Pesa prompt on your phone to activate your plan.');
    } catch (e) {
      errorMessage.value =
          'Payment didn\'t go through. Check the number and try again.';
    } finally {
      isPaying.value = false;
    }
  }

  /// Re-reads the signed-in user's Firestore doc (bypassing the in-memory
  /// cache) and moves on if the webhook has activated the subscription by
  /// now. There's no realtime channel to that confirmation, so this is a
  /// manual "I've paid" recovery action, not polling.
  Future<void> refreshStatus() async {
    isRefreshing.value = true;
    try {
      final refreshed = await _authRepo.refreshCurrentUser();
      if (refreshed?.hasActiveSubscription == true) {
        Get.offAllNamed(Routes.sellerShell);
      } else {
        Get.snackbar('Still pending',
            'We haven\'t received your payment confirmation yet. Try again in a moment.');
      }
    } finally {
      isRefreshing.value = false;
    }
  }
}
