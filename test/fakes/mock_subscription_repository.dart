import 'package:get/get.dart';
import 'mock_seed_data.dart';
import 'package:sellora/data/models/billing_history_entry_model.dart';
import 'package:sellora/data/models/billing_profile_model.dart';
import 'package:sellora/data/models/subscription_plan_model.dart';
import 'package:sellora/data/models/subscription_usage_model.dart';
import 'package:sellora/data/models/user_model.dart';
import 'package:sellora/data/repositories/auth_repository.dart';
import 'package:sellora/data/repositories/product_repository.dart';
import 'package:sellora/data/repositories/subscription_repository.dart';

class MockSubscriptionRepository extends GetxService
    implements SubscriptionRepository {
  MockSubscriptionRepository({AuthRepository? authRepository})
      : _authRepository = authRepository ?? Get.find<AuthRepository>();

  final AuthRepository _authRepository;
  final List<SubscriptionPlanModel> _plans = MockSeedData.plans();
  final List<BillingHistoryEntryModel> _history = [];
  final Map<String, BillingProfileModel> _billingProfiles = {};
  bool _cancelAtPeriodEnd = false;

  @override
  Future<List<SubscriptionPlanModel>> fetchPlans() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return SubscriptionPlanModel.sorted(_plans);
  }

  @override
  Future<BillingHistoryEntryModel> subscribeSeller({
    required String sellerId,
    required String planId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final plan = _plans.firstWhere((p) => p.id == planId);
    final now = DateTime.now();
    final entry = BillingHistoryEntryModel(
      id: 'mock-bh-${now.millisecondsSinceEpoch}',
      sellerId: sellerId,
      planId: planId,
      planName: plan.name,
      amountKes: plan.priceKes,
      amountUsd: plan.priceUsd,
      billingPeriodDays: plan.billingPeriodDays,
      status: 'paid',
      paymentProvider: 'INTASEND',
      paymentReference: 'MOCK-${now.millisecondsSinceEpoch}',
      createdAt: now,
      paidAt: now,
      invoiceNumber:
          'INV-${now.year}-${(_history.length + 1).toString().padLeft(6, '0')}',
      periodStart: now,
      periodEnd: now.add(Duration(days: plan.billingPeriodDays)),
    );
    _history.insert(0, entry);
    _cancelAtPeriodEnd = false;

    // Mock mode has no webhook to wait on, so this repository applies the
    // activation itself — the single place that does, instead of the
    // onboarding/subscription controllers each hand-reconstructing an
    // "active" UserModel afterward.
    final user = _authRepository.cachedUser;
    if (user != null && user.uid == sellerId) {
      await _authRepository.updateUser(user.copyWith(
        sellerStatus: SellerStatus.active,
        subscriptionPlanId: planId,
        subscriptionActiveUntil:
            now.add(Duration(days: plan.billingPeriodDays)),
      ));
    }
    return entry;
  }

  @override
  Future<void> updatePlan(SubscriptionPlanModel plan) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final index = _plans.indexWhere((p) => p.id == plan.id);
    if (index != -1) _plans[index] = plan;
  }

  @override
  Future<void> createPlan(SubscriptionPlanModel plan) async {
    if (_plans.any((p) => p.id == plan.id)) throw PlanIdTaken(plan.id);
    _plans.add(plan);
  }

  @override
  Future<SubscriptionUsageModel> fetchUsage(String sellerId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final user = _authRepository.cachedUser;
    SubscriptionPlanModel? plan;
    for (final p in _plans) {
      if (p.id == user?.subscriptionPlanId) {
        plan = p;
        break;
      }
    }
    final listings =
        await Get.find<ProductRepository>().sellerListings(sellerId);
    final until = user?.subscriptionActiveUntil;
    return SubscriptionUsageModel(
      listingCount: listings.where((p) => p.isListed).length,
      listingLimit: plan?.listingLimit ?? -1,
      orderLimit: plan?.orderLimit ?? -1,
      storeLimit: plan?.storeLimit ?? 1,
      subscriptionStatus: until == null
          ? 'none'
          : until.isAfter(DateTime.now())
              ? 'active'
              : 'lapsed',
      currentPeriodEnd: until,
      cancelAtPeriodEnd: _cancelAtPeriodEnd,
    );
  }

  @override
  Future<List<BillingHistoryEntryModel>> billingHistory(String sellerId,
          {int limit = 24}) async =>
      _history.where((e) => e.sellerId == sellerId).take(limit).toList();

  @override
  Future<void> cancelSubscription({String? reason}) async {
    final until = _authRepository.cachedUser?.subscriptionActiveUntil;
    if (until == null || !until.isAfter(DateTime.now())) {
      throw StateError('There is no running subscription to cancel');
    }
    _cancelAtPeriodEnd = true;
  }

  @override
  Future<void> resumeSubscription() async {
    final until = _authRepository.cachedUser?.subscriptionActiveUntil;
    if (until == null || !until.isAfter(DateTime.now())) {
      throw StateError('This subscription has ended');
    }
    _cancelAtPeriodEnd = false;
  }

  @override
  Future<BillingProfileModel?> fetchBillingProfile(String sellerId) async =>
      _billingProfiles[sellerId];

  @override
  Future<void> saveBillingProfile(BillingProfileModel profile) async =>
      _billingProfiles[profile.sellerId] = profile;
}
