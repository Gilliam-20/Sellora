import '../../../data/models/subscription_plan_model.dart';

/// What the admin plan editor collects, as typed. [PlanForm.build] checks
/// it against the same bounds the `subscription_plans` constraints enforce
/// (20261003000400_plan_config.sql), so a bad value is caught with a
/// readable message before it reaches the database. Pure, so it's tested
/// without a widget tree (test/plan_form_test.dart).
class PlanForm {
  PlanForm({
    required this.id,
    required this.name,
    required this.priceKes,
    required this.priceUsd,
    required this.billingPeriodDays,
    required this.listingLimit,
    required this.listingUnlimited,
    required this.orderLimit,
    required this.orderUnlimited,
    required this.storeLimit,
    required this.storeUnlimited,
    required this.supportLevel,
    required this.isPopular,
    required this.isActive,
    required this.sortOrder,
    required this.features,
    required this.perks,
  });

  /// Pre-filled from [plan], or blank for a new plan.
  factory PlanForm.from(SubscriptionPlanModel? plan) {
    String limitText(int? limit, String fallback) =>
        limit == null || limit < 0 ? fallback : '$limit';
    return PlanForm(
      id: plan?.id ?? '',
      name: plan?.name ?? '',
      priceKes: plan == null ? '' : _number(plan.priceKes),
      priceUsd: plan == null ? '' : _number(plan.priceUsd),
      billingPeriodDays: '${plan?.billingPeriodDays ?? 30}',
      listingLimit: limitText(plan?.listingLimit, '50'),
      listingUnlimited: (plan?.listingLimit ?? 0) < 0,
      orderLimit: limitText(plan?.orderLimit, '100'),
      orderUnlimited: (plan?.orderLimit ?? 0) < 0,
      storeLimit: limitText(plan?.storeLimit, '1'),
      storeUnlimited: (plan?.storeLimit ?? 1) < 0,
      supportLevel: plan?.supportLevel ?? PlanSupportLevel.standard,
      isPopular: plan?.isPopular ?? false,
      isActive: plan?.isActive ?? true,
      sortOrder: '${plan?.sortOrder ?? 0}',
      features: {
        for (final f in PlanFeature.known) f.key: false,
        ...?plan?.features,
      },
      perks: plan?.perks.join('\n') ?? '',
    );
  }

  String id;
  String name;
  String priceKes;
  String priceUsd;
  String billingPeriodDays;
  String listingLimit;
  bool listingUnlimited;
  String orderLimit;
  bool orderUnlimited;
  String storeLimit;
  bool storeUnlimited;
  PlanSupportLevel supportLevel;
  bool isPopular;
  bool isActive;
  String sortOrder;

  /// Known features first, then any custom flags.
  Map<String, bool> features;

  /// One perk per line.
  String perks;

  /// M-Pesa's floor and ceiling (`MPESA_MIN_KES`/`MPESA_MAX_KES` in
  /// `supabase/functions/_shared/intasendApi.js`). A plan priced outside
  /// them could never be paid for.
  static const minPriceKes = 10;
  static const maxPriceKes = 250000;
  static const maxPerks = 12;
  static const maxPerkLength = 80;
  static final idPattern = RegExp(r'^[a-z0-9][a-z0-9_-]{1,31}$');
  static final flagPattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,39}$');

  /// The plan this form describes, or the first problem with it.
  /// [takenIds] are the other plans' ids, checked only when [isNew].
  ({SubscriptionPlanModel? plan, String? error}) build(
      {required bool isNew, Iterable<String> takenIds = const []}) {
    ({SubscriptionPlanModel? plan, String? error}) fail(String error) =>
        (plan: null, error: error);

    final id = this.id.trim();
    if (isNew) {
      if (!idPattern.hasMatch(id)) {
        return fail('ID: 2-32 lowercase letters, digits, - or _, '
            'starting with a letter or digit');
      }
      if (takenIds.contains(id)) return fail('A plan with ID "$id" exists');
    }
    final name = this.name.trim();
    if (name.isEmpty || name.length > 40) {
      return fail('Name: 1-40 characters');
    }

    final kes = double.tryParse(priceKes.trim());
    if (kes == null || kes < minPriceKes || kes > maxPriceKes) {
      return fail('KES price: $minPriceKes to $maxPriceKes, the range '
          'M-Pesa accepts');
    }
    final usdText = priceUsd.trim();
    final usd = usdText.isEmpty ? 0.0 : double.tryParse(usdText);
    if (usd == null || usd < 0) return fail('USD price: 0 or more');

    final period = int.tryParse(billingPeriodDays.trim());
    if (period == null || period < 1 || period > 366) {
      return fail('Billing period: 1 to 366 days');
    }

    final listings = _limit(listingLimit, listingUnlimited, min: 0);
    if (listings == null) {
      return fail('Listed products: a whole number, 0 or more');
    }
    final orders = _limit(orderLimit, orderUnlimited, min: 0);
    if (orders == null) return fail('Paid orders: a whole number, 0 or more');
    final stores = _limit(storeLimit, storeUnlimited, min: 1);
    if (stores == null) return fail('Stores: a whole number, 1 or more');

    final sort =
        int.tryParse(sortOrder.trim().isEmpty ? '0' : sortOrder.trim());
    if (sort == null) return fail('Display order: a whole number');

    for (final key in features.keys) {
      if (!flagPattern.hasMatch(key)) {
        return fail('Feature flag "$key": letters, digits and _, '
            'starting with a letter');
      }
    }

    final perkLines = perks
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (perkLines.length > maxPerks) {
      return fail('Perks: at most $maxPerks lines');
    }
    if (perkLines.any((l) => l.length > maxPerkLength)) {
      return fail('Perks: each line at most $maxPerkLength characters');
    }

    return (
      plan: SubscriptionPlanModel(
        id: id,
        name: name,
        priceKes: kes,
        priceUsd: usd,
        billingPeriodDays: period,
        listingLimit: listings,
        orderLimit: orders,
        storeLimit: stores,
        perks: perkLines,
        isPopular: isPopular,
        features: Map.of(features),
        supportLevel: supportLevel,
        isActive: isActive,
        sortOrder: sort,
      ),
      error: null,
    );
  }

  static int? _limit(String text, bool unlimited, {required int min}) {
    if (unlimited) return SubscriptionPlanModel.unlimited;
    final value = int.tryParse(text.trim());
    return value == null || value < min ? null : value;
  }

  static String _number(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}
