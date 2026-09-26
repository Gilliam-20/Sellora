import 'package:flutter/foundation.dart' show debugPrint;
import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../core/i18n/countries.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/store_model.dart';
import '../../../data/models/subscription_plan_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/store_repository.dart';
import '../../../data/repositories/subscription_repository.dart';
import '../../../data/services/intasend_service.dart';

enum OnboardingStep { storeSetup, choosePlan, pay, pendingConfirmation }

class SellerOnboardingController extends GetxController {
  SellerOnboardingController({
    SubscriptionRepository? subscriptionRepository,
    AuthRepository? authRepository,
    StoreRepository? storeRepository,
  })  : _subscriptionRepo =
            subscriptionRepository ?? Get.find<SubscriptionRepository>(),
        _authRepo = authRepository ?? Get.find<AuthRepository>(),
        _storeRepo = storeRepository ?? Get.find<StoreRepository>();

  final SubscriptionRepository _subscriptionRepo;
  final AuthRepository _authRepo;
  final StoreRepository _storeRepo;

  final plans = <SubscriptionPlanModel>[].obs;
  final selectedPlanId = RxnString();
  final step = OnboardingStep.storeSetup.obs;
  final isLoading = true.obs;
  final isPaying = false.obs;
  final isRefreshing = false.obs;
  final errorMessage = RxnString();

  // ---- Store setup ------------------------------------------------------
  /// The seller's store, or null if they somehow have none yet (every
  /// sign-up creates one, but the seller shell routes here to recover if a
  /// store is ever missing — see [saveStoreSetup]).
  final store = Rxn<StoreModel>();
  final storeName = ''.obs;
  final category = RxnString();
  final countryCode = Countries.kenya.code.obs;
  final currencyCode = Countries.kenya.currency.obs;
  final isSavingStore = false.obs;

  // ---- Email verification ----------------------------------------------
  /// Starts true so the banner doesn't flash before the first check.
  final isEmailVerified = true.obs;
  final verificationSent = false.obs;

  SubscriptionPlanModel? get selectedPlan =>
      plans.firstWhereOrNull((p) => p.id == selectedPlanId.value);

  String? get email => _authRepo.cachedUser?.email;

  @override
  void onInit() {
    super.onInit();
    _load();
    checkEmailVerified();
  }

  Future<void> _load() async {
    isLoading.value = true;
    try {
      final user = _authRepo.cachedUser;
      final results = await Future.wait([
        _subscriptionRepo.fetchPlans(),
        if (user != null) _storeRepo.storesForSeller(user.uid),
      ]);
      plans.value = results[0] as List<SubscriptionPlanModel>;
      selectedPlanId.value = plans.firstWhereOrNull((p) => p.isPopular)?.id ??
          plans.firstOrNull?.id;

      final existing = results.length > 1
          ? (results[1] as List<StoreModel>).firstOrNull
          : null;
      store.value = existing;
      storeName.value = existing?.name ?? user?.storeName ?? '';
      category.value = existing?.category;
      if (existing?.countryCode != null) {
        countryCode.value = existing!.countryCode!;
        currencyCode.value = existing.currencyCode;
      }
      // A seller who already set their store up (e.g. back here after a
      // lapsed subscription) goes straight to plan selection.
      step.value = existing != null && existing.isSetUp
          ? OnboardingStep.choosePlan
          : OnboardingStep.storeSetup;
    } catch (e) {
      debugPrint('SellerOnboardingController._load: $e');
      errorMessage.value = 'We couldn\'t load your account. Please try again.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> retryLoad() {
    errorMessage.value = null;
    return _load();
  }

  void selectCountry(String code) {
    final country = Countries.byCode(code);
    if (country == null) return;
    countryCode.value = country.code;
    // Default the store currency to the country's own; the seller can
    // still pick another one afterwards.
    currencyCode.value = country.currency;
  }

  /// Saves the store profile (name, category, country, currency). Creates
  /// the store if the seller has none, so the shell's "no store" dead end
  /// has a way out. The slug is never changed here — renaming a store keeps
  /// its public address.
  Future<void> saveStoreSetup() async {
    final user = _authRepo.cachedUser;
    final name = storeName.value.trim();
    if (user == null) return;
    if (name.length < 2 || category.value == null) {
      errorMessage.value = 'Add a store name and pick a category.';
      return;
    }
    isSavingStore.value = true;
    errorMessage.value = null;
    try {
      final existing = store.value;
      if (existing == null) {
        store.value = await createStoreForSeller(
          _storeRepo,
          sellerId: user.uid,
          storeName: name,
          category: category.value,
          countryCode: countryCode.value,
          currencyCode: currencyCode.value,
        );
      } else {
        final updated = existing.copyWith(
          name: name,
          category: category.value,
          countryCode: countryCode.value,
          currencyCode: currencyCode.value,
        );
        await _storeRepo.updateStore(updated);
        store.value = updated;
      }
      if (user.storeName != name || user.currencyCode != currencyCode.value) {
        await _authRepo.updateUser(
            user.copyWith(storeName: name, currencyCode: currencyCode.value));
      }
      if (user.hasActiveSubscription) {
        Get.offAllNamed(Routes.sellerShell);
      } else {
        step.value = OnboardingStep.choosePlan;
      }
    } catch (e) {
      debugPrint('SellerOnboardingController.saveStoreSetup: $e');
      errorMessage.value = 'We couldn\'t save your store. Please try again.';
    } finally {
      isSavingStore.value = false;
    }
  }

  Future<void> checkEmailVerified() async {
    try {
      isEmailVerified.value = await _authRepo.checkEmailVerified();
    } catch (e) {
      debugPrint('SellerOnboardingController.checkEmailVerified: $e');
    }
  }

  Future<void> resendVerification() async {
    try {
      await _authRepo.resendVerificationEmail();
      verificationSent.value = true;
    } catch (e) {
      debugPrint('SellerOnboardingController.resendVerification: $e');
      Get.snackbar('Couldn\'t send email',
          'Wait a few minutes before requesting another link.');
    }
  }

  void selectPlan(String planId) => selectedPlanId.value = planId;

  void goToPayment() => step.value = OnboardingStep.pay;

  /// The previous step, or null where there's nowhere to go back to.
  OnboardingStep? get previousStep => switch (step.value) {
        OnboardingStep.choosePlan => OnboardingStep.storeSetup,
        OnboardingStep.pay => OnboardingStep.choosePlan,
        _ => null,
      };

  void goBack() {
    final previous = previousStep;
    if (previous == null) return;
    errorMessage.value = null;
    step.value = previous;
  }

  Future<void> payWithMpesa(String phone) async {
    final plan = selectedPlan;
    final user = _authRepo.cachedUser;
    if (plan == null || user == null) return;

    isPaying.value = true;
    errorMessage.value = null;
    try {
      final entry = await _subscriptionRepo.subscribeSeller(
          sellerId: user.uid, planId: plan.id);

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

  /// Re-reads the signed-in user's profile (bypassing the in-memory
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
