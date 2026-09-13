import 'package:get/get.dart';
import '../../mock/mock_seed_data.dart';
import '../../models/billing_history_entry_model.dart';
import '../../models/subscription_plan_model.dart';
import '../../models/subscription_usage_model.dart';
import '../../models/user_model.dart';
import '../auth_repository.dart';
import '../product_repository.dart';
import '../subscription_repository.dart';

class MockSubscriptionRepository extends GetxService
    implements SubscriptionRepository {
  MockSubscriptionRepository({AuthRepository? authRepository})
      : _authRepository = authRepository ?? Get.find<AuthRepository>();

  final AuthRepository _authRepository;
  final List<SubscriptionPlanModel> _plans = MockSeedData.plans();

  @override
  Future<List<SubscriptionPlanModel>> fetchPlans() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _plans;
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
    );

    // Mock mode has no webhook to wait on, so this repository applies the
    // activation itself — the single place that does, instead of the
    // onboarding/subscription controllers each hand-reconstructing an
    // "active" UserModel afterward.
    final user = _authRepository.cachedUser;
    if (user != null && user.uid == sellerId) {
      await _authRepository.updateUser(user.copyWith(
        sellerStatus: SellerStatus.active,
        subscriptionPlanId: planId,
        subscriptionActiveUntil: now.add(Duration(days: plan.billingPeriodDays)),
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
    final listings = await Get.find<ProductRepository>().sellerListings(sellerId);
    return SubscriptionUsageModel(
      listingCount: listings.length,
      listingLimit: plan?.listingLimit ?? -1,
    );
  }
}
