import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/subscription_plan_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/subscription_repository.dart';
import '../../../data/services/intasend_service.dart';

enum OnboardingStep { choosePlan, pay }

class SellerOnboardingController extends GetxController {
  final SubscriptionRepository _subscriptionRepo =
      Get.find<SubscriptionRepository>();
  final AuthRepository _authRepo = Get.find<AuthRepository>();

  final plans = <SubscriptionPlanModel>[].obs;
  final selectedPlanId = RxnString();
  final step = OnboardingStep.choosePlan.obs;
  final isLoadingPlans = true.obs;
  final isPaying = false.obs;
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
      String reference;
      if (AppConstants.useMockData) {
        await Future.delayed(const Duration(seconds: 2));
        reference = 'MOCK-${DateTime.now().millisecondsSinceEpoch}';
      } else {
        final intasend = Get.find<IntasendService>();
        final result = await intasend.collectMpesa(
          phone: Formatters.toMpesaFormat(phone),
          amountKes: plan.priceKes,
          narrative: 'Sellora ${plan.name} plan subscription',
        );
        reference = result.reference;
      }

      await _subscriptionRepo.subscribeSeller(
          sellerId: user.uid, planId: plan.id, paymentReference: reference);

      final updated = user.copyWith(
        subscriptionPlanId: plan.id,
        subscriptionActiveUntil:
            DateTime.now().add(Duration(days: plan.billingPeriodDays)),
      );
      final activeUser = UserModel(
        uid: updated.uid,
        name: updated.name,
        email: updated.email,
        role: updated.role,
        phone: updated.phone,
        photoUrl: updated.photoUrl,
        sellerStatus: SellerStatus.active,
        storeName: updated.storeName,
        subscriptionPlanId: plan.id,
        subscriptionActiveUntil:
            DateTime.now().add(Duration(days: plan.billingPeriodDays)),
        currencyCode: updated.currencyCode,
        createdAt: updated.createdAt,
      );
      await _authRepo.updateUser(activeUser);

      Get.offAllNamed(Routes.sellerShell);
      Get.snackbar('You\'re live',
          'Your ${plan.name} subscription is active — start listing products.');
    } catch (e) {
      errorMessage.value =
          'Payment didn\'t go through. Check the number and try again.';
    } finally {
      isPaying.value = false;
    }
  }
}
