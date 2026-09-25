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
    required this.commissionPercent,
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

  /// -1 means unlimited listings.
  final int listingLimit;
  final double commissionPercent;
  final List<String> perks;
  final bool isPopular;

  /// -1 means unlimited orders per billing period. Not yet enforced —
  /// `createOrder` has no seller/store attribution to count against (see
  /// WORKLOG.md, 2026-09-12).
  final int orderLimit;

  /// -1 means unlimited stores. Schema-only, unenforced: a seller can only
  /// ever have one store today, and multi-store-per-seller is still an open
  /// decision (SELLORA_IMPLEMENTATION_PLAN.md).
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
    double? commissionPercent,
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
      commissionPercent: commissionPercent ?? this.commissionPercent,
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
      commissionPercent: (map['commissionPercent'] as num?)?.toDouble() ?? 5,
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
        'commissionPercent': commissionPercent,
        'perks': perks,
        'isPopular': isPopular,
        'orderLimit': orderLimit,
        'storeLimit': storeLimit,
        'features': features,
      };
}
