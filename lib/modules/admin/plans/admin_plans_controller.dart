import 'package:get/get.dart';
import '../../../data/models/subscription_plan_model.dart';
import '../../../data/models/fee_settings.dart';
import '../../../data/repositories/fee_repository.dart';
import '../../../data/repositories/subscription_repository.dart';
import 'plan_form.dart';

class AdminPlansController extends GetxController {
  AdminPlansController(
      {SubscriptionRepository? subscriptionRepository,
      FeeRepository? feeRepository})
      : _subscriptionRepo =
            subscriptionRepository ?? Get.find<SubscriptionRepository>(),
        _feeRepo = feeRepository ?? Get.find<FeeRepository>();

  final SubscriptionRepository _subscriptionRepo;
  final FeeRepository _feeRepo;

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

  /// Saves [form] as a new plan or over an existing one (TODO.md §16).
  /// Returns an error to show, or null once saved. Marking a plan "most
  /// popular" takes the badge off any other, since onboarding preselects
  /// the first popular plan it finds.
  Future<String?> savePlan(PlanForm form, {required bool isNew}) async {
    final result = form.build(
        isNew: isNew, takenIds: plans.map((p) => p.id));
    final plan = result.plan;
    if (plan == null) return result.error;
    final error = _offerRefusal(plan);
    if (error != null) return error;

    isSaving.value = true;
    try {
      if (isNew) {
        await _subscriptionRepo.createPlan(plan);
      } else {
        await _subscriptionRepo.updatePlan(plan);
      }
      if (plan.isPopular) {
        for (final other in plans.where((p) => p.isPopular && p.id != plan.id)) {
          await _subscriptionRepo.updatePlan(other.copyWith(isPopular: false));
        }
      }
      await load();
      return null;
    } on PlanIdTaken catch (e) {
      return e.toString();
    } catch (e) {
      return 'Couldn\'t save ${plan.name}. $e';
    } finally {
      isSaving.value = false;
    }
  }

  /// Retires [plan] (no longer sold; current subscribers keep it and may
  /// renew) or offers it again. Returns an error to show, or null.
  Future<String?> setActive(SubscriptionPlanModel plan, bool active) async {
    final updated = plan.copyWith(isActive: active);
    final error = _offerRefusal(updated);
    if (error != null) return error;
    isSaving.value = true;
    try {
      await _subscriptionRepo.updatePlan(updated);
      await load();
      return null;
    } catch (e) {
      return 'Couldn\'t update ${plan.name}. $e';
    } finally {
      isSaving.value = false;
    }
  }

  /// With no active plan, onboarding has nothing to offer and no new
  /// seller can start.
  String? _offerRefusal(SubscriptionPlanModel changed) {
    if (changed.isActive) return null;
    final othersOnOffer =
        plans.where((p) => p.isActive && p.id != changed.id).isNotEmpty;
    return othersOnOffer
        ? null
        : 'Keep at least one plan on offer, or new sellers can\'t sign up.';
  }
}
