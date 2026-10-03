import 'package:flutter_test/flutter_test.dart';
import 'package:sellora/core/utils/plan_text.dart';
import 'package:sellora/data/models/fee_settings.dart';
import 'package:sellora/data/models/subscription_plan_model.dart';
import 'package:sellora/data/repositories/fee_repository.dart';
import 'package:sellora/modules/admin/plans/admin_plans_controller.dart';
import 'package:sellora/modules/admin/plans/plan_form.dart';
import 'fakes/mock_auth_repository.dart';
import 'fakes/mock_store_repository.dart';
import 'fakes/mock_subscription_repository.dart';

SubscriptionPlanModel _plan(String id,
        {double kes = 1300,
        int sort = 0,
        bool active = true,
        bool popular = false}) =>
    SubscriptionPlanModel(
      id: id,
      name: id,
      priceUsd: 0,
      priceKes: kes,
      billingPeriodDays: 30,
      listingLimit: 50,
      perks: const [],
      sortOrder: sort,
      isActive: active,
      isPopular: popular,
    );

class _FakeFees implements FeeRepository {
  @override
  Future<FeeSettings> settings() async =>
      const FeeSettings(serviceFeeRate: 0.07, chargeOnShipping: false);

  @override
  Future<void> update(FeeSettings settings) async {}
}

void main() {
  group('SubscriptionPlanModel', () {
    test('round-trips support level, active flag and display order', () {
      final plan = _plan('growth', sort: 20, active: false).copyWith(
          supportLevel: PlanSupportLevel.priority,
          features: {'advancedAnalytics': true});
      final restored = SubscriptionPlanModel.fromMap(plan.toMap());
      expect(restored.supportLevel, PlanSupportLevel.priority);
      expect(restored.isActive, isFalse);
      expect(restored.sortOrder, 20);
      expect(restored.hasFeature('advancedAnalytics'), isTrue);
      expect(restored.hasFeature('customDomain'), isFalse);
    });

    test('a row from before the plan config migration reads as offered', () {
      final plan = SubscriptionPlanModel.fromMap(
          {'id': 'old', 'name': 'Old', 'supportLevel': 'gold'});
      expect(plan.isActive, isTrue);
      expect(plan.sortOrder, 0);
      expect(plan.supportLevel, PlanSupportLevel.standard);
    });

    test('sorts by display order, then price', () {
      final sorted = SubscriptionPlanModel.sorted([
        _plan('pro', sort: 30, kes: 10300),
        _plan('cheap', sort: 10, kes: 500),
        _plan('starter', sort: 10, kes: 1300),
      ]);
      expect(sorted.map((p) => p.id), ['cheap', 'starter', 'pro']);
    });

    test('offers active plans, plus a retired one only to its holder', () {
      final plans = [_plan('old', active: false), _plan('starter')];
      expect(
          SubscriptionPlanModel.offered(plans).map((p) => p.id), ['starter']);
      expect(
          SubscriptionPlanModel.offered(plans, currentPlanId: 'old')
              .map((p) => p.id),
          ['old', 'starter']);
    });
  });

  group('PlanText', () {
    test('names the billing period', () {
      expect(PlanText.period(30), 'month');
      expect(PlanText.period(365), 'year');
      expect(PlanText.period(45), '45 days');
    });

    test('lists the configured limits, features, support and perks', () {
      final plan = SubscriptionPlanModel(
        id: 'growth',
        name: 'Growth',
        priceUsd: 31,
        priceKes: 4000,
        billingPeriodDays: 30,
        listingLimit: 500,
        orderLimit: 1000,
        storeLimit: 1,
        features: const {'advancedAnalytics': true, 'customDomain': false},
        supportLevel: PlanSupportLevel.priority,
        perks: const ['Early access'],
      );
      expect(PlanText.highlights(plan), [
        '500 listed products',
        '1000 paid orders per month',
        '1 store',
        'Advanced analytics (coming soon)',
        'Priority support',
        'Early access',
      ]);
    });

    test('unlimited reads as such, and internal flags are never listed', () {
      final plan = _plan('pro').copyWith(
          listingLimit: -1,
          orderLimit: -1,
          storeLimit: -1,
          features: {'betaThemes': true});
      final lines = PlanText.highlights(plan);
      expect(lines.take(3), [
        'Unlimited listed products',
        'Unlimited paid orders per month',
        'Unlimited stores',
      ]);
      expect(lines.join(), isNot(contains('betaThemes')));
    });
  });

  group('PlanForm', () {
    PlanForm valid() => PlanForm.from(null)
      ..id = 'business'
      ..name = ' Business '
      ..priceKes = '2500'
      ..priceUsd = '19.5';

    test('builds a plan from what was typed', () {
      final result = (valid()
            ..orderUnlimited = true
            ..storeLimit = '3'
            ..perks = 'Early access\n\n  Onboarding call  ')
          .build(isNew: true);
      final plan = result.plan!;
      expect(result.error, isNull);
      expect(plan.name, 'Business');
      expect(plan.priceKes, 2500);
      expect(plan.priceUsd, 19.5);
      expect(plan.listingLimit, 50);
      expect(plan.orderLimit, -1);
      expect(plan.storeLimit, 3);
      expect(plan.perks, ['Early access', 'Onboarding call']);
      expect(plan.features.keys,
          containsAll(['customDomain', 'advancedAnalytics']));
    });

    test('round-trips an existing plan unchanged', () {
      final original = _plan('starter')
          .copyWith(orderLimit: -1, supportLevel: PlanSupportLevel.dedicated);
      final plan = PlanForm.from(original).build(isNew: false).plan!;
      expect(plan.toMap()..remove('features'),
          original.toMap()..remove('features'));
    });

    test('refuses what the database would', () {
      String? error(void Function(PlanForm f) change) =>
          (valid()..apply(change)).build(isNew: true).error;
      expect(error((f) => f.id = 'Big Plan'), contains('ID'));
      expect(error((f) => f.name = '  '), contains('Name'));
      expect(error((f) => f.priceKes = '5'), contains('M-Pesa'));
      expect(error((f) => f.priceUsd = '-1'), contains('USD'));
      expect(error((f) => f.billingPeriodDays = '0'), contains('period'));
      expect(error((f) => f.listingLimit = '-3'), contains('Listed'));
      expect(error((f) => f.storeLimit = '0'), contains('Stores'));
      expect(error((f) => f.perks = List.filled(13, 'x').join('\n')),
          contains('12'));
      expect(error((f) => f.features['bad flag'] = true), contains('flag'));
    });

    test('a new plan may not reuse an id', () {
      expect(valid().build(isNew: true, takenIds: ['business']).error,
          contains('exists'));
      // Editing keeps its own id.
      expect(valid().build(isNew: false, takenIds: ['business']).error, isNull);
    });
  });

  group('AdminPlansController', () {
    late MockSubscriptionRepository repo;
    late AdminPlansController controller;

    setUp(() async {
      repo = MockSubscriptionRepository(
          authRepository:
              MockAuthRepository(storeRepository: MockStoreRepository()));
      controller = AdminPlansController(
          subscriptionRepository: repo, feeRepository: _FakeFees());
      await controller.load();
    });

    test('creates a plan, and refuses a duplicate id', () async {
      final form = PlanForm.from(null)
        ..id = 'business'
        ..name = 'Business'
        ..priceKes = '2500';
      expect(await controller.savePlan(form, isNew: true), isNull);
      expect(controller.plans.map((p) => p.id), contains('business'));
      expect(await controller.savePlan(form, isNew: true), contains('exists'));
    });

    test('one plan holds the most-popular badge at a time', () async {
      final starter = controller.plans.firstWhere((p) => p.id == 'starter');
      final form = PlanForm.from(starter)..isPopular = true;
      expect(await controller.savePlan(form, isNew: false), isNull);
      expect(controller.plans.where((p) => p.isPopular).map((p) => p.id),
          ['starter']);
    });

    test('retires a plan, but never the last one on offer', () async {
      for (final id in ['starter', 'growth']) {
        final plan = controller.plans.firstWhere((p) => p.id == id);
        expect(await controller.setActive(plan, false), isNull);
      }
      final last = controller.plans.firstWhere((p) => p.isActive);
      expect(await controller.setActive(last, false), contains('at least one'));
      expect(controller.plans.where((p) => p.isActive), hasLength(1));
    });
  });
}

extension on PlanForm {
  void apply(void Function(PlanForm f) change) => change(this);
}
