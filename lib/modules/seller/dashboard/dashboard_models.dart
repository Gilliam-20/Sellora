/// Preset windows for the dashboard's date-range filter (TODO.md §9).
/// [custom] pairs with [SellerDashboardController.customRange] rather than
/// carrying its own bounds, so this stays a plain enum.
enum DateRangeOption {
  today,
  yesterday,
  last7,
  last30,
  last90,
  thisYear,
  custom
}

extension DateRangeOptionX on DateRangeOption {
  String get label => switch (this) {
        DateRangeOption.today => 'Today',
        DateRangeOption.yesterday => 'Yesterday',
        DateRangeOption.last7 => 'Last 7 days',
        DateRangeOption.last30 => 'Last 30 days',
        DateRangeOption.last90 => 'Last 90 days',
        DateRangeOption.thisYear => 'This year',
        DateRangeOption.custom => 'Custom',
      };
}

/// One bucket of the sales-over-time chart — a day's (or, for "This year",
/// a month's) paid revenue.
class SalesPoint {
  SalesPoint(this.bucketStart, this.amount);
  final DateTime bucketStart;
  final double amount;
}

/// Aggregated performance of one product across the orders in the current
/// date range, for the dashboard's "Top products" list.
class TopProductStat {
  TopProductStat({
    required this.productId,
    required this.title,
    required this.imageUrl,
    required this.quantitySold,
    required this.revenue,
  });

  final String productId;
  final String title;
  final String imageUrl;
  final int quantitySold;
  final double revenue;
}
