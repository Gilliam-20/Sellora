import 'package:get/get.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/subscription_plan_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/subscription_repository.dart';
import '../../../data/services/intasend_service.dart';

class SellerSubscriptionController extends GetxController {
  final SubscriptionRepository _subscriptionRepo =
      Get.find<SubscriptionRepository>();
  final AuthRepository authRepo = Get.find<AuthRepository>();

  final plans = <SubscriptionPlanModel>[].obs;
  final isLoading = true.obs;
  final isPaying = false.obs;

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
    isLoading.value = false;
  }

  Future<void> switchPlan(SubscriptionPlanModel plan, String mpesaPhone) async {
    final user = authRepo.cachedUser;
    if (user == null) return;
    isPaying.value = true;
    try {
      String reference;
      if (AppConstants.useMockData) {
        await Future.delayed(const Duration(seconds: 2));
        reference = 'MOCK-${DateTime.now().millisecondsSinceEpoch}';
      } else {
        final intasend = Get.find<IntasendService>();
        final result = await intasend.collectMpesa(
          phone: Formatters.toMpesaFormat(mpesaPhone),
          amountKes: plan.priceKes,
          narrative: 'Sellora ${plan.name} plan',
        );
        reference = result.reference;
      }
      await _subscriptionRepo.subscribeSeller(
          sellerId: user.uid, planId: plan.id, paymentReference: reference);

      final updated = UserModel(
        uid: user.uid,
        name: user.name,
        email: user.email,
        role: user.role,
        phone: user.phone,
        photoUrl: user.photoUrl,
        sellerStatus: SellerStatus.active,
        storeName: user.storeName,
        subscriptionPlanId: plan.id,
        subscriptionActiveUntil:
            DateTime.now().add(Duration(days: plan.billingPeriodDays)),
        currencyCode: user.currencyCode,
        createdAt: user.createdAt,
      );
      await authRepo.updateUser(updated);
      Get.back();
      Get.snackbar('Plan updated', 'You\'re now on the ${plan.name} plan.');
    } finally {
      isPaying.value = false;
    }
  }
}
