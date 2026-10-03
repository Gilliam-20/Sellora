/// The admin Overview's money figures, computed server-side by
/// `admin_platform_metrics` (supabase/migrations/20261003000200_admin_platform.sql)
/// over every paid order. Everything is in KES: `orders.total_kes` is what
/// IntaSend actually charged, and the fee is the USD snapshot at the
/// order's own FX rate — the only figures comparable across orders priced
/// in different shopper currencies.
class PlatformMetrics {
  const PlatformMetrics({
    required this.days,
    required this.lifetime,
    required this.window,
    required this.series,
    required this.subscriptions,
  });

  /// The length of [window] and [series], in days.
  final int days;
  final PlatformTotals lifetime;
  final PlatformTotals window;

  /// One point per day (Africa/Nairobi), oldest first, zero-filled.
  final List<PlatformDay> series;
  final SubscriptionHealth subscriptions;

  static const empty = PlatformMetrics(
    days: 0,
    lifetime: PlatformTotals.zero,
    window: PlatformTotals.zero,
    series: [],
    subscriptions: SubscriptionHealth.zero,
  );

  factory PlatformMetrics.fromMap(Map<String, dynamic> map) => PlatformMetrics(
        days: (map['days'] as num?)?.toInt() ?? 0,
        lifetime: PlatformTotals.fromMap(_map(map['lifetime'])),
        window: PlatformTotals.fromMap(_map(map['window'])),
        series: [
          for (final point in (map['series'] as List?) ?? const [])
            PlatformDay.fromMap(_map(point)),
        ],
        subscriptions: SubscriptionHealth.fromMap(_map(map['subscriptions'])),
      );
}

class PlatformTotals {
  const PlatformTotals({
    required this.gmvKes,
    required this.serviceFeesKes,
    required this.refundsKes,
    required this.paidOrders,
  });

  /// What buyers paid into seller stores — seller money, not Sellora's.
  final double gmvKes;

  /// Sellora's 7% of the goods, snapshotted on each order.
  final double serviceFeesKes;
  final double refundsKes;
  final int paidOrders;

  static const zero = PlatformTotals(
      gmvKes: 0, serviceFeesKes: 0, refundsKes: 0, paidOrders: 0);

  factory PlatformTotals.fromMap(Map<String, dynamic> map) => PlatformTotals(
        gmvKes: _num(map['gmvKes']),
        serviceFeesKes: _num(map['serviceFeesKes']),
        refundsKes: _num(map['refundsKes']),
        paidOrders: _num(map['paidOrders']).toInt(),
      );
}

class PlatformDay {
  const PlatformDay({
    required this.day,
    required this.gmvKes,
    required this.serviceFeesKes,
    required this.orders,
  });

  final DateTime day;
  final double gmvKes;
  final double serviceFeesKes;
  final int orders;

  factory PlatformDay.fromMap(Map<String, dynamic> map) {
    // A bare `YYYY-MM-DD`: parsed as a local calendar day, not an instant.
    final parts = (map['day'] as String? ?? '').split('-');
    final day = parts.length == 3
        ? DateTime(
            int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]))
        : DateTime.fromMillisecondsSinceEpoch(0);
    return PlatformDay(
      day: day,
      gmvKes: _num(map['gmvKes']),
      serviceFeesKes: _num(map['serviceFeesKes']),
      orders: _num(map['orders']).toInt(),
    );
  }
}

/// Seller subscriptions: who's paying now, who stopped in the last 30 days.
class SubscriptionHealth {
  const SubscriptionHealth({
    required this.active,
    required this.lapsed30d,
    required this.mrrKes,
  });

  final int active;

  /// Subscriptions whose period ended in the last 30 days without renewal.
  final int lapsed30d;

  /// Active plans' prices normalized to 30 days.
  final double mrrKes;

  /// Share of the sellers who were subscribed over the last 30 days that
  /// have since lapsed. Null with nobody to measure.
  double? get churnRate {
    final base = active + lapsed30d;
    return base == 0 ? null : lapsed30d / base;
  }

  static const zero = SubscriptionHealth(active: 0, lapsed30d: 0, mrrKes: 0);

  factory SubscriptionHealth.fromMap(Map<String, dynamic> map) =>
      SubscriptionHealth(
        active: _num(map['active']).toInt(),
        lapsed30d: _num(map['lapsed30d']).toInt(),
        mrrKes: _num(map['mrrKes']),
      );
}

// Postgres numerics arrive as JSON numbers inside jsonb, but be lenient
// about strings too.
double _num(Object? value) => switch (value) {
      num n => n.toDouble(),
      String s => double.tryParse(s) ?? 0,
      _ => 0,
    };

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};
