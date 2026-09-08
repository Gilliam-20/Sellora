/// A subscription tier a seller pays monthly for. Kept data-driven
/// (fetched from Firestore, editable by admins in the Plans module)
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
      };
}
