/// How much support a plan promises. A commitment to the seller, shown on
/// plan cards; nothing in the app switches on it.
enum PlanSupportLevel {
  standard('standard', 'Email support'),
  priority('priority', 'Priority support'),
  dedicated('dedicated', 'Dedicated support');

  const PlanSupportLevel(this.value, this.label);

  /// The `subscription_plans.support_level` value.
  final String value;
  final String label;

  static PlanSupportLevel parse(Object? value) => PlanSupportLevel.values
      .firstWhere((l) => l.value == value, orElse: () => standard);
}

/// A feature flag Sellora knows how to describe to sellers. A plan's
/// `features` map may also hold flags that aren't listed here: those are
/// internal switches, editable by admins and readable through
/// [SubscriptionPlanModel.hasFeature], but never advertised.
class PlanFeature {
  const PlanFeature(this.key, this.label, {this.isBuilt = false});

  final String key;
  final String label;

  /// Whether the app actually delivers this yet. One that isn't is still
  /// configurable per plan, but sellers see it marked "coming soon" rather
  /// than paying for something that doesn't exist.
  final bool isBuilt;

  static const customDomain = PlanFeature('customDomain', 'Custom domain');
  static const advancedAnalytics =
      PlanFeature('advancedAnalytics', 'Advanced analytics');

  static const known = [customDomain, advancedAnalytics];

  static PlanFeature? byKey(String key) =>
      known.where((f) => f.key == key).firstOrNull;
}

/// A subscription tier a seller pays for each billing period. Kept
/// data-driven (the `subscription_plans` table, edited by admins under
/// Admin → Plans) rather than hardcoded, so pricing and limits can change
/// without an app release (TODO.md §16).
class SubscriptionPlanModel {
  SubscriptionPlanModel({
    required this.id,
    required this.name,
    required this.priceUsd,
    required this.priceKes,
    required this.billingPeriodDays,
    required this.listingLimit,
    required this.perks,
    this.isPopular = false,
    this.orderLimit = -1,
    this.storeLimit = 1,
    this.features = const {},
    this.supportLevel = PlanSupportLevel.standard,
    this.isActive = true,
    this.sortOrder = 0,
  });

  /// Value meaning "no limit" for [listingLimit], [orderLimit] and
  /// [storeLimit].
  static const unlimited = -1;

  final String id;
  final String name;

  /// What a seller is charged: subscriptions settle in KES only.
  final double priceKes;

  /// Reference price shown alongside; never charged.
  final double priceUsd;
  final int billingPeriodDays;

  /// -1 means unlimited listings. Enforced server-side on publish (a
  /// trigger on `products`); drafts don't count.
  final int listingLimit;

  /// Extra marketing lines. The limits, features and support level are
  /// listed from their own fields, so these shouldn't repeat them.
  final List<String> perks;
  final bool isPopular;

  /// -1 means unlimited paid orders per billing period. Enforced by
  /// `createOrder` (the `seller_order_gate` SQL function) against the limit
  /// snapshotted when the seller last paid, so a change reaches existing
  /// subscribers at their next payment.
  final int orderLimit;

  /// -1 means unlimited stores, otherwise at least 1. Enforced by the
  /// `stores` insert policy; multi-store-per-seller is still an open
  /// product decision (SELLORA_IMPLEMENTATION_PLAN.md).
  final int storeLimit;

  /// Feature flags by key; see [PlanFeature].
  final Map<String, bool> features;
  final PlanSupportLevel supportLevel;

  /// False once retired: no longer offered to new subscribers, though
  /// sellers already on it keep it and may renew.
  final bool isActive;

  /// Display order on plan lists, lowest first.
  final int sortOrder;

  bool hasFeature(String key) => features[key] ?? false;

  /// Plans in display order: [sortOrder], then price.
  static List<SubscriptionPlanModel> sorted(
          Iterable<SubscriptionPlanModel> plans) =>
      plans.toList()
        ..sort((a, b) {
          final byOrder = a.sortOrder.compareTo(b.sortOrder);
          return byOrder != 0 ? byOrder : a.priceKes.compareTo(b.priceKes);
        });

  /// The plans a seller may choose from: every active plan, plus
  /// [currentPlanId]'s even if it was retired, since its holder may renew.
  static List<SubscriptionPlanModel> offered(
          Iterable<SubscriptionPlanModel> plans,
          {String? currentPlanId}) =>
      sorted(plans.where((p) => p.isActive || p.id == currentPlanId));

  SubscriptionPlanModel copyWith({
    String? name,
    double? priceUsd,
    double? priceKes,
    int? billingPeriodDays,
    int? listingLimit,
    List<String>? perks,
    bool? isPopular,
    int? orderLimit,
    int? storeLimit,
    Map<String, bool>? features,
    PlanSupportLevel? supportLevel,
    bool? isActive,
    int? sortOrder,
  }) {
    return SubscriptionPlanModel(
      id: id,
      name: name ?? this.name,
      priceUsd: priceUsd ?? this.priceUsd,
      priceKes: priceKes ?? this.priceKes,
      billingPeriodDays: billingPeriodDays ?? this.billingPeriodDays,
      listingLimit: listingLimit ?? this.listingLimit,
      perks: perks ?? this.perks,
      isPopular: isPopular ?? this.isPopular,
      orderLimit: orderLimit ?? this.orderLimit,
      storeLimit: storeLimit ?? this.storeLimit,
      features: features ?? this.features,
      supportLevel: supportLevel ?? this.supportLevel,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  factory SubscriptionPlanModel.fromMap(Map<String, dynamic> map) {
    return SubscriptionPlanModel(
      id: map['id'] as String,
      name: map['name'] as String,
      priceUsd: (map['priceUsd'] as num?)?.toDouble() ?? 0,
      priceKes: (map['priceKes'] as num?)?.toDouble() ?? 0,
      billingPeriodDays: map['billingPeriodDays'] as int? ?? 30,
      listingLimit: map['listingLimit'] as int? ?? 25,
      perks: List<String>.from(map['perks'] as List? ?? []),
      isPopular: map['isPopular'] as bool? ?? false,
      orderLimit: map['orderLimit'] as int? ?? -1,
      storeLimit: map['storeLimit'] as int? ?? 1,
      features: Map<String, bool>.from(map['features'] as Map? ?? {}),
      supportLevel: PlanSupportLevel.parse(map['supportLevel']),
      isActive: map['isActive'] as bool? ?? true,
      sortOrder: map['sortOrder'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'priceUsd': priceUsd,
        'priceKes': priceKes,
        'billingPeriodDays': billingPeriodDays,
        'listingLimit': listingLimit,
        'perks': perks,
        'isPopular': isPopular,
        'orderLimit': orderLimit,
        'storeLimit': storeLimit,
        'features': features,
        'supportLevel': supportLevel.value,
        'isActive': isActive,
        'sortOrder': sortOrder,
      };
}
