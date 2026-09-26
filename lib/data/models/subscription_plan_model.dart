/// A subscription tier a seller pays monthly for. Kept data-driven
/// (fetched from Supabase, editable by admins in the Plans module)
/// rather than hardcoded, so pricing can change without an app release.
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
  });

  final String id;
  final String name;
  final double priceUsd;
  final double priceKes;
  final int billingPeriodDays;

  /// -1 means unlimited listings. Enforced server-side on publish (a
  /// trigger on `products`); drafts don't count.
  final int listingLimit;
  final List<String> perks;
  final bool isPopular;

  /// -1 means unlimited paid orders per billing period. Enforced by
  /// `createOrder` (the `seller_order_gate` SQL function).
  final int orderLimit;

  /// -1 means unlimited stores. Enforced by the `stores` insert policy;
  /// multi-store-per-seller is still an open product decision
  /// (SELLORA_IMPLEMENTATION_PLAN.md).
  final int storeLimit;

  /// Feature flags (e.g. `customDomain`, `advancedAnalytics`). Plumbing
  /// only — nothing reads these yet.
  final Map<String, bool> features;

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
      };
}
