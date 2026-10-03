import 'package:get/get.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/billing_history_entry_model.dart';
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
  final history = <BillingHistoryEntryModel>[].obs;
  final isLoading = true.obs;
  final isPaying = false.obs;
  final isRefreshing = false.obs;
  final errorMessage = RxnString();

  SubscriptionPlanModel? get currentPlan => plans
      .firstWhereOrNull((p) => p.id == authRepo.cachedUser?.subscriptionPlanId);

  /// What the seller can buy: active plans, plus their own if it's been
  /// retired (they may still renew it).
  List<SubscriptionPlanModel> get offeredPlans => SubscriptionPlanModel.offered(
      plans,
      currentPlanId: authRepo.cachedUser?.subscriptionPlanId);

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    try {
      plans.value = await _subscriptionRepo.fetchPlans();
      final uid = authRepo.cachedUser?.uid;
      if (uid != null) {
        final results = await Future.wait([
          _subscriptionRepo.fetchUsage(uid),
          _subscriptionRepo.billingHistory(uid),
        ]);
        usage.value = results[0] as SubscriptionUsageModel;
        history.value = results[1] as List<BillingHistoryEntryModel>;
      }
    } finally {
      isLoading.value = false;
    }
  }

  /// Buys [plan] — a switch, or a renewal when it's the current plan. Paying
  /// before the period ends adds a period to its end rather than restarting
  /// it, so renewing early loses nothing.
  Future<void> switchPlan(SubscriptionPlanModel plan, String mpesaPhone) async {
    final user = authRepo.cachedUser;
    if (user == null) return;
    isPaying.value = true;
    errorMessage.value = null;
    try {
      final entry = await _subscriptionRepo.subscribeSeller(
          sellerId: user.uid, planId: plan.id);

      await Get.find<IntasendService>().payBillingMpesa(
        billingEntryId: entry.id,
        phone: Formatters.toMpesaFormat(mpesaPhone),
      );
      // No live confirmation channel — same fire-and-forget pattern as
      // onboarding and buyer checkout. refreshStatus() is the recovery path.
      Get.back();
      Get.snackbar('Almost there',
          'Complete the M-Pesa prompt on your phone, then tap "Refresh status" below.');
    } on ApiException catch (e) {
      // A 4xx carries the server's own caller-facing reason, e.g. a
      // downgrade refused until the seller unlists some products.
      final status = e.statusCode;
      errorMessage.value = status != null && status >= 400 && status < 500
          ? e.message
          : 'Payment didn\'t go through. Check the number and try again.';
    } catch (e) {
      errorMessage.value =
          'Payment didn\'t go through. Check the number and try again.';
    } finally {
      isPaying.value = false;
    }
  }

  /// Re-reads the signed-in user's profile (bypassing the in-memory
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
