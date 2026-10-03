import '../../data/models/subscription_plan_model.dart';
import 'plan_text.dart';

/// What moving from the seller's current plan to [to] means: whether it's an
/// upgrade, what they gain, what they give up. Pure, so the billing page's
/// wording is unit-tested (test/billing_page_test.dart).
enum PlanChangeKind { start, renew, upgrade, downgrade, switchPlan }

class PlanChange {
  const PlanChange({required this.from, required this.to});

  /// The plan held now; null for a seller without one.
  final SubscriptionPlanModel? from;
  final SubscriptionPlanModel to;

  /// Ranked by price per day, so a yearly plan isn't mistaken for an
  /// upgrade just for costing more in one payment. Equal prices are a
  /// switch.
  PlanChangeKind get kind {
    final current = from;
    if (current == null) return PlanChangeKind.start;
    if (current.id == to.id) return PlanChangeKind.renew;
    final diff = _daily(to).compareTo(_daily(current));
    if (diff > 0) return PlanChangeKind.upgrade;
    if (diff < 0) return PlanChangeKind.downgrade;
    return PlanChangeKind.switchPlan;
  }

  String get actionLabel => switch (kind) {
        PlanChangeKind.start => 'Choose',
        PlanChangeKind.renew => 'Renew',
        PlanChangeKind.upgrade => 'Upgrade',
        PlanChangeKind.downgrade => 'Downgrade',
        PlanChangeKind.switchPlan => 'Switch',
      };

  /// What [to] adds over [from], one line each: raised limits, features it
  /// turns on, better support. Empty for a renewal or a new seller.
  List<String> get gains => _compare(better: true);

  /// What [to] takes away compared with [from].
  List<String> get losses => _compare(better: false);

  List<String> _compare({required bool better}) {
    final current = from;
    if (current == null || current.id == to.id) return const [];
    final per = PlanText.period(to.billingPeriodDays);
    final limits = [
      _limitLine(current.listingLimit, to.listingLimit, 'listed product',
          'listed products', better),
      _limitLine(current.orderLimit, to.orderLimit, 'paid order', 'paid orders',
          better,
          suffix: ' per $per'),
      _limitLine(current.storeLimit, to.storeLimit, 'store', 'stores', better),
    ];
    return [
      ...limits.whereType<String>(),
      for (final f in PlanFeature.known)
        if (to.hasFeature(f.key) != current.hasFeature(f.key) &&
            to.hasFeature(f.key) == better)
          better ? PlanText.feature(f) : 'No ${f.label.toLowerCase()}',
      if (to.supportLevel.index != current.supportLevel.index &&
          (to.supportLevel.index > current.supportLevel.index) == better)
        '${to.supportLevel.label} instead of '
            '${current.supportLevel.label.toLowerCase()}',
    ];
  }

  static String? _limitLine(
      int from, int to, String singular, String plural, bool better,
      {String suffix = ''}) {
    final cmp = _cap(to).compareTo(_cap(from));
    if (cmp == 0 || (cmp > 0) != better) return null;
    final was = from < 0 ? 'unlimited' : '$from';
    return '${PlanText.limit(to, singular, plural)}$suffix '
        '(${better ? 'up' : 'down'} from $was)';
  }

  /// Unlimited (-1) ranks above any number.
  static double _cap(int limit) =>
      limit < 0 ? double.infinity : limit.toDouble();

  static double _daily(SubscriptionPlanModel plan) =>
      plan.priceKes /
      (plan.billingPeriodDays <= 0 ? 30 : plan.billingPeriodDays);

  /// The cheapest of [plans] (other than [current]) whose limit, read by
  /// [limitOf], is above [used]: what to suggest when a seller is close to
  /// running out. Null when nothing offered has more room.
  static SubscriptionPlanModel? roomFor(
    Iterable<SubscriptionPlanModel> plans, {
    required SubscriptionPlanModel? current,
    required int Function(SubscriptionPlanModel) limitOf,
    required int used,
  }) {
    SubscriptionPlanModel? best;
    for (final plan in plans) {
      if (plan.id == current?.id || !plan.isActive) continue;
      final limit = limitOf(plan);
      if (limit >= 0 && limit <= used) continue;
      if (current != null && _cap(limit) <= _cap(limitOf(current))) continue;
      if (best == null || _daily(plan) < _daily(best)) best = plan;
    }
    return best;
  }
}
