import '../../../core/i18n/countries.dart';
import '../../../data/models/order_model.dart';

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

/// Paid sales into one destination country, for the dashboard's "Sales by
/// country" card.
class CountrySales {
  const CountrySales({
    required this.countryCode,
    required this.countryName,
    required this.orders,
    required this.revenue,
  });

  /// ISO 3166-1 alpha-2, or '' when an order carried none.
  final String countryCode;
  final String countryName;
  final int orders;

  /// In the store's currency.
  final double revenue;

  /// Groups [paidOrders] by shipping country, biggest revenue first.
  /// [toStoreCurrency] converts each order's total into the store's
  /// currency, since orders are priced in the shopper's.
  static List<CountrySales> fromOrders(
    Iterable<OrderModel> paidOrders,
    double Function(double amount, String currency) toStoreCurrency,
  ) {
    final byCountry = <String, ({int orders, double revenue})>{};
    for (final order in paidOrders) {
      final code = order.shippingAddress.countryCode.trim().toUpperCase();
      final current = byCountry[code] ?? (orders: 0, revenue: 0.0);
      byCountry[code] = (
        orders: current.orders + 1,
        revenue: current.revenue + toStoreCurrency(order.total, order.currency),
      );
    }
    final list = [
      for (final entry in byCountry.entries)
        CountrySales(
          countryCode: entry.key,
          countryName: entry.key.isEmpty
              ? 'Unknown'
              : Countries.byCode(entry.key)?.name ?? entry.key,
          orders: entry.value.orders,
          revenue: entry.value.revenue,
        ),
    ]..sort((a, b) {
        final byRevenue = b.revenue.compareTo(a.revenue);
        return byRevenue != 0 ? byRevenue : b.orders.compareTo(a.orders);
      });
    return list;
  }
}
