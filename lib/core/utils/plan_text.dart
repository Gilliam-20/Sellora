import '../../data/models/subscription_plan_model.dart';

/// How a plan is described to sellers, built from its configured fields so
/// a card can never advertise a limit the server doesn't enforce. Pure, so
/// it's unit-tested without a widget tree (test/plan_text_test.dart).
class PlanText {
  PlanText._();

  /// "month" for a 30-day plan, "year" for 365, else "45 days".
  static String period(int days) => switch (days) {
        1 => 'day',
        7 => 'week',
        30 => 'month',
        365 || 366 => 'year',
        _ => '$days days',
      };

  /// "50 listed products", "1 store", "Unlimited stores".
  static String limit(int limit, String singular, String plural) {
    if (limit < 0) return 'Unlimited $plural';
    return '$limit ${limit == 1 ? singular : plural}';
  }

  /// A feature's line: its label, marked when the app doesn't deliver it
  /// yet.
  static String feature(PlanFeature feature) =>
      feature.isBuilt ? feature.label : '${feature.label} (coming soon)';

  /// Every line a plan card lists: limits, the known features it turns on,
  /// support, then the admin's own extra perks.
  static List<String> highlights(SubscriptionPlanModel plan) => [
        limit(plan.listingLimit, 'listed product', 'listed products'),
        '${limit(plan.orderLimit, 'paid order', 'paid orders')} '
            'per ${period(plan.billingPeriodDays)}',
        limit(plan.storeLimit, 'store', 'stores'),
        for (final f in PlanFeature.known)
          if (plan.hasFeature(f.key)) feature(f),
        plan.supportLevel.label,
        ...plan.perks,
      ];
}
