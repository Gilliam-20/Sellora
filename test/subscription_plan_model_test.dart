import 'package:flutter_test/flutter_test.dart';
import 'package:sellora/data/models/subscription_plan_model.dart';

void main() {
  test('fromMap defaults orderLimit/storeLimit/features when absent from an older plan doc',
      () {
    final plan = SubscriptionPlanModel.fromMap({
      'id': 'starter',
      'name': 'Starter',
      'priceUsd': 9.99,
      'priceKes': 1300,
      'billingPeriodDays': 30,
      'listingLimit': 25,
      'commissionPercent': 7,
      'perks': ['Some perk'],
    });

    expect(plan.orderLimit, -1);
    expect(plan.storeLimit, 1);
    expect(plan.features, isEmpty);
  });

  test('toMap/fromMap round-trips every field, including the new ones', () {
    final plan = SubscriptionPlanModel(
      id: 'growth',
      name: 'Growth',
      priceUsd: 29.99,
      priceKes: 3250,
      billingPeriodDays: 30,
      listingLimit: 200,
      commissionPercent: 5,
      perks: const ['Perk A', 'Perk B'],
      isPopular: true,
      orderLimit: 500,
      storeLimit: 1,
      features: const {'customDomain': false, 'advancedAnalytics': true},
    );

    final restored = SubscriptionPlanModel.fromMap(plan.toMap());

    expect(restored.id, plan.id);
    expect(restored.orderLimit, 500);
    expect(restored.storeLimit, 1);
    expect(restored.features, {'customDomain': false, 'advancedAnalytics': true});
    expect(restored.isPopular, isTrue);
  });

  test('copyWith only overrides the fields passed', () {
    final plan = SubscriptionPlanModel(
      id: 'scale',
      name: 'Scale',
      priceUsd: 79,
      priceKes: 10300,
      billingPeriodDays: 30,
      listingLimit: -1,
      commissionPercent: 3,
      perks: const [],
      orderLimit: -1,
      storeLimit: 1,
    );

    final updated = plan.copyWith(orderLimit: 1000);

    expect(updated.orderLimit, 1000);
    expect(updated.storeLimit, 1);
    expect(updated.priceKes, 10300);
    expect(updated.id, 'scale');
  });
}
