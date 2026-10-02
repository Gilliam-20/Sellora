/// How a discount code reduces an order (TODO.md §27). Stored as the
/// `discounts.kind` column's text.
enum DiscountKind { percentage, fixedAmount }

extension DiscountKindX on DiscountKind {
  String get label => switch (this) {
        DiscountKind.percentage => 'Percentage',
        DiscountKind.fixedAmount => 'Fixed amount',
      };

  String get column => switch (this) {
        DiscountKind.percentage => 'percentage',
        DiscountKind.fixedAmount => 'fixed_amount',
      };

  static DiscountKind parse(Object? value) => value == 'fixed_amount'
      ? DiscountKind.fixedAmount
      : DiscountKind.percentage;
}

/// Where a code stands, for the seller's list.
enum DiscountStatus { active, scheduled, ended, usedUp, off }

extension DiscountStatusX on DiscountStatus {
  String get label => switch (this) {
        DiscountStatus.active => 'Active',
        DiscountStatus.scheduled => 'Scheduled',
        DiscountStatus.ended => 'Ended',
        DiscountStatus.usedUp => 'Used up',
        DiscountStatus.off => 'Off',
      };
}

/// One cart line, as a discount sees it.
typedef DiscountLine = ({String productId, double lineTotal});

/// What applying a code to a cart comes to: an [amount] to take off, or a
/// [refusal] to show the buyer.
typedef DiscountQuote = ({double amount, String? refusal});

/// A store's discount code (`discounts` table,
/// supabase/migrations/20261003000100_discounts.sql). The seller funds it out
/// of their margin. `createOrder` prices it server-side
/// (supabase/functions/_shared/discounts.js); [quote] mirrors that for the
/// checkout preview only.
///
/// [value] (for a fixed amount) and [minSubtotal] are in the listings'
/// currency, which is USD today.
class DiscountModel {
  DiscountModel({
    this.id = '',
    required this.storeId,
    required this.code,
    required this.kind,
    required this.value,
    this.minSubtotal = 0,
    this.productIds = const [],
    DateTime? startsAt,
    this.endsAt,
    this.usageLimit,
    this.oncePerCustomer = false,
    this.isActive = true,
    this.createdAt,
  }) : startsAt = startsAt ?? DateTime.now();

  final String id;
  final String storeId;
  final String code;
  final DiscountKind kind;
  final double value;
  final double minSubtotal;

  /// Empty means every product in the store.
  final List<String> productIds;
  final DateTime startsAt;
  final DateTime? endsAt;

  /// Total orders that may use the code; null is unlimited.
  final int? usageLimit;
  final bool oncePerCustomer;
  final bool isActive;
  final DateTime? createdAt;

  /// Same rule as the `discounts.code` check constraint.
  static final codePattern = RegExp(r'^[A-Z0-9][A-Z0-9_-]{2,31}$');

  /// What a buyer or seller typed, as stored.
  static String normalizeCode(String raw) => raw.trim().toUpperCase();

  static const notApplicable =
      'This discount code doesn\'t apply to anything in your cart';

  /// Whether the code is usable at [now], ignoring usage limits.
  bool isLiveAt(DateTime now) =>
      isActive &&
      !startsAt.isAfter(now) &&
      (endsAt == null || endsAt!.isAfter(now));

  /// Where the code stands at [now], given [uses] live orders so far.
  DiscountStatus statusAt(DateTime now, {int uses = 0}) {
    if (!isActive) return DiscountStatus.off;
    if (endsAt != null && !endsAt!.isAfter(now)) return DiscountStatus.ended;
    if (usageLimit != null && uses >= usageLimit!) return DiscountStatus.usedUp;
    if (startsAt.isAfter(now)) return DiscountStatus.scheduled;
    return DiscountStatus.active;
  }

  /// "10% off", "USD 5.00 off".
  String get summary => kind == DiscountKind.percentage
      ? '${_trim(value)}% off'
      : 'USD ${value.toStringAsFixed(2)} off';

  /// The checkout preview of what this code takes off [lines]. The same
  /// rules as `priceDiscount` in supabase/functions/_shared/discounts.js:
  /// the minimum is measured on the whole subtotal, the discount on the
  /// eligible lines only, and never more than they cost.
  DiscountQuote quote(List<DiscountLine> lines) {
    final subtotal = _round2(lines.fold(0.0, (sum, l) => sum + l.lineTotal));
    if (subtotal < minSubtotal) {
      return (
        amount: 0.0,
        refusal: 'This discount code needs an order of at least '
            'USD ${minSubtotal.toStringAsFixed(2)} before shipping',
      );
    }
    final only = productIds.toSet();
    final eligible = _round2(lines
        .where((l) => only.isEmpty || only.contains(l.productId))
        .fold(0.0, (sum, l) => sum + l.lineTotal));
    if (eligible <= 0) return (amount: 0.0, refusal: notApplicable);
    final amount = kind == DiscountKind.percentage
        ? _round2(eligible * (value > 100 ? 100 : value) / 100)
        : _round2(value);
    return (amount: amount > eligible ? eligible : amount, refusal: null);
  }

  DiscountModel copyWith({bool? isActive}) => DiscountModel(
        id: id,
        storeId: storeId,
        code: code,
        kind: kind,
        value: value,
        minSubtotal: minSubtotal,
        productIds: productIds,
        startsAt: startsAt,
        endsAt: endsAt,
        usageLimit: usageLimit,
        oncePerCustomer: oncePerCustomer,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'storeId': storeId,
        'code': code,
        'kind': kind.column,
        'value': value,
        'minSubtotal': minSubtotal,
        'productIds': productIds,
        'startsAt': startsAt.toIso8601String(),
        'endsAt': endsAt?.toIso8601String(),
        'usageLimit': usageLimit,
        'oncePerCustomer': oncePerCustomer,
        'isActive': isActive,
        'createdAt': createdAt?.toIso8601String(),
      };

  /// Reads both a `discounts` row (after `fromRow`) and the
  /// `storefront_discount()` answer, which has no id, store or limits.
  factory DiscountModel.fromMap(Map<String, dynamic> map) => DiscountModel(
        id: map['id'] as String? ?? '',
        storeId: map['storeId'] as String? ?? '',
        code: map['code'] as String? ?? '',
        kind: DiscountKindX.parse(map['kind']),
        value: (map['value'] as num?)?.toDouble() ?? 0,
        minSubtotal: (map['minSubtotal'] as num?)?.toDouble() ?? 0,
        productIds: (map['productIds'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        startsAt: DateTime.tryParse(map['startsAt'] as String? ?? ''),
        endsAt: DateTime.tryParse(map['endsAt'] as String? ?? '')?.toLocal(),
        usageLimit: (map['usageLimit'] as num?)?.toInt(),
        oncePerCustomer: map['oncePerCustomer'] as bool? ?? false,
        isActive: map['isActive'] as bool? ?? true,
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? ''),
      );

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
