import '../../../data/models/order_model.dart';
import '../../../data/models/store_customer_model.dart';

/// Converts [amount] in [currency] into the store's reporting currency.
typedef ToStoreCurrency = double Function(double amount, String currency);

/// One customer of a store, as their orders describe them (TODO.md §24).
class CustomerStat {
  CustomerStat({
    required this.uid,
    required this.name,
    required this.email,
    required this.orders,
    required this.purchaseCount,
    required this.totalSpent,
    this.joinedAt,
    this.firstPurchaseAt,
    this.lastOrderAt,
  });

  final String uid;
  final String name;
  final String email;
  final DateTime? joinedAt;

  /// Every order they placed with the store, newest first, paid or not.
  final List<OrderModel> orders;

  /// Orders whose payment went through (see [CustomerAnalytics.isPurchase]).
  final int purchaseCount;

  /// What those purchases came to, in the store's currency.
  final double totalSpent;
  final DateTime? firstPurchaseAt;
  final DateTime? lastOrderAt;

  double get averageOrderValue =>
      purchaseCount == 0 ? 0 : totalSpent / purchaseCount;

  bool get isReturning => purchaseCount >= 2;
}

/// The headline numbers above the customer list.
class CustomerSummary {
  CustomerSummary({
    required this.totalCustomers,
    required this.purchasingCustomers,
    required this.returningCustomers,
    required this.newCustomers,
    required this.averageSpend,
  });

  /// Registered with the store, or bought from it.
  final int totalCustomers;

  /// Made at least one purchase.
  final int purchasingCustomers;

  /// Made two or more.
  final int returningCustomers;

  /// First purchase within the window [CustomerAnalytics.build] was given.
  final int newCustomers;

  /// Total spent per purchasing customer, in the store's currency.
  final double averageSpend;

  /// Share of purchasing customers who came back, 0–1.
  double get repeatRate =>
      purchasingCustomers == 0 ? 0 : returningCustomers / purchasingCustomers;
}

enum CustomerSort { totalSpent, orders, recent, name }

extension CustomerSortX on CustomerSort {
  String get label => switch (this) {
        CustomerSort.totalSpent => 'Total spent',
        CustomerSort.orders => 'Orders',
        CustomerSort.recent => 'Most recent',
        CustomerSort.name => 'Name',
      };
}

/// Builds the store's customer list from its registered customers and its
/// orders. Pure, so it's tested without a backend.
class CustomerAnalytics {
  CustomerAnalytics._(this.customers, this.summary);

  final List<CustomerStat> customers;
  final CustomerSummary summary;

  /// A purchase is an order whose payment went through, including one
  /// later partly refunded. Matches the dashboard's "paid" reading.
  static bool isPurchase(OrderModel order) =>
      order.paymentStatus == OrderPaymentStatus.paid ||
      order.paymentStatus == OrderPaymentStatus.partiallyRefunded;

  /// [newWithin] is the window for [CustomerSummary.newCustomers], ending
  /// at [now].
  factory CustomerAnalytics.build({
    required List<StoreCustomerModel> members,
    required List<OrderModel> orders,
    required ToStoreCurrency toStoreCurrency,
    DateTime? now,
    Duration newWithin = const Duration(days: 30),
  }) {
    final byBuyer = <String, List<OrderModel>>{};
    for (final order in orders) {
      byBuyer.putIfAbsent(order.buyerId, () => []).add(order);
    }
    final membersById = {for (final m in members) m.uid: m};
    final ids = {...membersById.keys, ...byBuyer.keys};

    final stats = <CustomerStat>[];
    for (final uid in ids) {
      final member = membersById[uid];
      final theirs = [...?byBuyer[uid]]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final purchases = theirs.where(isPurchase).toList();
      // Someone who bought without a membership row (an account removed
      // since, say) is still a customer; their name comes off the order.
      final fallbackName = theirs
          .map((o) => o.shippingAddress.fullName)
          .firstWhere((n) => n.isNotEmpty, orElse: () => '');
      stats.add(CustomerStat(
        uid: uid,
        name: (member?.name.isNotEmpty ?? false)
            ? member!.name
            : (fallbackName.isNotEmpty ? fallbackName : 'Customer'),
        email: member?.email ?? '',
        joinedAt: member?.createdAt,
        orders: theirs,
        purchaseCount: purchases.length,
        totalSpent: purchases.fold(
            0.0, (sum, o) => sum + toStoreCurrency(o.total, o.currency)),
        firstPurchaseAt: purchases.isEmpty ? null : purchases.last.createdAt,
        lastOrderAt: theirs.isEmpty ? null : theirs.first.createdAt,
      ));
    }

    final since = (now ?? DateTime.now()).subtract(newWithin);
    final purchasing = stats.where((c) => c.purchaseCount > 0).toList();
    final spent = purchasing.fold(0.0, (sum, c) => sum + c.totalSpent);
    final summary = CustomerSummary(
      totalCustomers: stats.length,
      purchasingCustomers: purchasing.length,
      returningCustomers: purchasing.where((c) => c.isReturning).length,
      newCustomers:
          purchasing.where((c) => !c.firstPurchaseAt!.isBefore(since)).length,
      averageSpend: purchasing.isEmpty ? 0 : spent / purchasing.length,
    );
    return CustomerAnalytics._(sort(stats, CustomerSort.totalSpent), summary);
  }

  /// [customers] matching [query] (name or email), in [order].
  static List<CustomerStat> filter(
      List<CustomerStat> customers, String query, CustomerSort order) {
    final q = query.trim().toLowerCase();
    final matched = q.isEmpty
        ? customers
        : customers
            .where((c) =>
                c.name.toLowerCase().contains(q) ||
                c.email.toLowerCase().contains(q))
            .toList();
    return sort(matched, order);
  }

  static List<CustomerStat> sort(
      List<CustomerStat> customers, CustomerSort order) {
    final sorted = [...customers];
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    int byRecent(CustomerStat a, CustomerStat b) =>
        (b.lastOrderAt ?? b.joinedAt ?? epoch)
            .compareTo(a.lastOrderAt ?? a.joinedAt ?? epoch);
    sorted.sort(switch (order) {
      CustomerSort.totalSpent => (a, b) {
          final c = b.totalSpent.compareTo(a.totalSpent);
          return c != 0 ? c : byRecent(a, b);
        },
      CustomerSort.orders => (a, b) {
          final c = b.purchaseCount.compareTo(a.purchaseCount);
          return c != 0 ? c : byRecent(a, b);
        },
      CustomerSort.recent => byRecent,
      CustomerSort.name => (a, b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    });
    return sorted;
  }
}
