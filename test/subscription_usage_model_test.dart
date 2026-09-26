import 'package:flutter_test/flutter_test.dart';
import 'package:sellora/data/models/subscription_usage_model.dart';

void main() {
  test('reads my_plan_usage()', () {
    final usage = SubscriptionUsageModel.fromMap({
      'planId': 'growth',
      'subscriptionStatus': 'active',
      'currentPeriodEnd': '2026-10-26T18:37:25.709+00:00',
      'billingPeriodDays': 30,
      'listingCount': 3,
      'listingLimit': 100,
      'orderCount': 4,
      'orderLimit': -1,
      'storeCount': 1,
      'storeLimit': 2,
    });
    expect(usage.isActive, isTrue);
    expect(usage.listingCount, 3);
    expect(usage.listingLimit, 100);
    expect(usage.orderCount, 4);
    expect(usage.orderLimit, -1);
    expect(usage.storeLimit, 2);
    expect(usage.currentPeriodEnd!.toUtc(),
        DateTime.utc(2026, 10, 26, 18, 37, 25, 709));
  });

  test('a seller who never subscribed has no period and default limits', () {
    final usage = SubscriptionUsageModel.fromMap({
      'planId': null,
      'subscriptionStatus': 'none',
      'currentPeriodEnd': null,
      'listingCount': 0,
      'listingLimit': -1,
      'orderCount': 0,
      'orderLimit': -1,
      'storeCount': 1,
      'storeLimit': 1,
    });
    expect(usage.isActive, isFalse);
    expect(usage.currentPeriodEnd, isNull);
    expect(usage.billingPeriodDays, 30);
  });
}
