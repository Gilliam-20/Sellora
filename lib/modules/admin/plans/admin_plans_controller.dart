import 'package:get/get.dart';
import '../../../data/models/subscription_plan_model.dart';
import '../../../data/models/fee_settings.dart';
import '../../../data/repositories/fee_repository.dart';
import '../../../data/repositories/subscription_repository.dart';

class AdminPlansController extends GetxController {
  final SubscriptionRepository _subscriptionRepo =
      Get.find<SubscriptionRepository>();

  final FeeRepository _feeRepo = Get.find<FeeRepository>();

  final plans = <SubscriptionPlanModel>[].obs;
  final isLoading = true.obs;
  final isSaving = false.obs;

  /// The service fee in force (TODO.md §15). Null until loaded.
  final fees = Rxn<FeeSettings>();
  final feeError = RxnString();
  final isSavingFees = false.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    plans.value = await _subscriptionRepo.fetchPlans();
    isLoading.value = false;
    loadFees();
  }

  Future<void> loadFees() async {
    feeError.value = null;
    try {
      fees.value = await _feeRepo.settings();
    } catch (e) {
      feeError.value = 'Couldn\'t load the service fee. $e';
    }
  }

  /// [percent] is e.g. 7 for 7%. Returns an error to show, or null once
  /// saved. Applies to orders placed from now on only.
  Future<String?> saveFees(
      {required double percent, required bool chargeOnShipping}) async {
    final rate = percent / 100;
    if (!rate.isFinite || rate < 0 || rate > FeeSettings.maxServiceFeeRate) {
      return 'Enter a rate from 0 to '
          '${(FeeSettings.maxServiceFeeRate * 100).toStringAsFixed(0)}%';
    }
    isSavingFees.value = true;
    try {
      final settings = FeeSettings(
          serviceFeeRate: (rate * 10000).round() / 10000,
          chargeOnShipping: chargeOnShipping);
      await _feeRepo.update(settings);
      fees.value = settings;
      return null;
    } catch (e) {
      return 'Couldn\'t save the service fee. $e';
    } finally {
      isSavingFees.value = false;
    }
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
