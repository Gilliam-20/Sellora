import 'package:flutter/material.dart' show DateTimeRange;
import 'package:get/get.dart';
import '../../../data/models/order_model.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/subscription_plan_model.dart';
import '../../../data/models/subscription_usage_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/repositories/subscription_repository.dart';
import '../../storefront/store_scope.dart';
import 'dashboard_models.dart';

class SellerDashboardController extends GetxController {
  SellerDashboardController({
    OrderRepository? orderRepository,
    ProductRepository? productRepository,
    SubscriptionRepository? subscriptionRepository,
    AuthRepository? authRepository,
    StoreScope? storeScope,
  })  : _orderRepo = orderRepository ?? Get.find<OrderRepository>(),
        _productRepo = productRepository ?? Get.find<ProductRepository>(),
        _subscriptionRepo =
            subscriptionRepository ?? Get.find<SubscriptionRepository>(),
        authRepo = authRepository ?? Get.find<AuthRepository>(),
        _storeScope = storeScope ?? Get.find<StoreScope>();

  final OrderRepository _orderRepo;
  final ProductRepository _productRepo;
  final SubscriptionRepository _subscriptionRepo;
  final AuthRepository authRepo;
  final StoreScope _storeScope;

  final isLoading = true.obs;

  // ---- Date-range filter --------------------------------------------------
  final selectedRange = DateRangeOption.today.obs;
  final Rxn<DateTimeRange> customRange = Rxn<DateTimeRange>();

  // ---- Metrics for the selected range --------------------------------------
  final grossSales = 0.0.obs;
  final netRevenue = 0.0.obs;
  final orderCount = 0.obs;
  final paidOrderCount = 0.obs;
  final averageOrderValue = 0.0.obs;
  final cancelledCount = 0.obs;
  final statusBreakdown = <OrderStatus, int>{}.obs;
  final topProducts = <TopProductStat>[].obs;
  final salesSeries = <SalesPoint>[].obs;

  /// Percent change vs. the immediately preceding period of the same
  /// length. Null when there's nothing in the prior period to compare
  /// against (division by zero would be meaningless, not "0%").
  final Rxn<double> grossSalesDeltaPercent = Rxn<double>();
  final Rxn<double> ordersDeltaPercent = Rxn<double>();

  // ---- Not range-filtered: always the current operational state ----------
  final recentOrders = <OrderModel>[].obs;
  final listingCount = 0.obs;

  /// Orders awaiting fulfillment right now — an operational queue, not a
  /// historical metric, so it deliberately ignores the date-range filter.
  final pendingFulfillmentCount = 0.obs;

  // ---- Store health / subscription -----------------------------------------
  final Rxn<SubscriptionUsageModel> usage = Rxn<SubscriptionUsageModel>();
  final Rxn<SubscriptionPlanModel> plan = Rxn<SubscriptionPlanModel>();
  final ordersThisPeriod = 0.obs;

  // ---- Guided setup checklist ------------------------------------------
  final hasProduct = false.obs;
  final hasPublishedProduct = false.obs;
  final hasCustomizedStore = false.obs;
  final hasSale = false.obs;

  List<OrderModel> _allOrders = [];

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    final user = authRepo.cachedUser;
    if (user == null) return;
    isLoading.value = true;

    final results = await Future.wait([
      _orderRepo.sellerOrders(user.uid),
      _productRepo.sellerListings(user.uid),
      _subscriptionRepo.fetchUsage(user.uid),
      _subscriptionRepo.fetchPlans(),
    ]);

    _allOrders = (results[0] as List<OrderModel>)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final listings = results[1] as List<ProductModel>;
    usage.value = results[2] as SubscriptionUsageModel;
    final plans = results[3] as List<SubscriptionPlanModel>;
    SubscriptionPlanModel? matchedPlan;
    for (final p in plans) {
      if (p.id == user.subscriptionPlanId) {
        matchedPlan = p;
        break;
      }
    }
    plan.value = matchedPlan;

    recentOrders.value = _allOrders.take(5).toList();
    listingCount.value = listings.where((l) => l.isListed).length;
    pendingFulfillmentCount.value = _allOrders
        .where((o) =>
            o.status == OrderStatus.pending ||
            o.status == OrderStatus.processing)
        .length;

    hasProduct.value = listings.isNotEmpty;
    hasPublishedProduct.value = listings.any((l) => l.isListed);
    hasSale.value =
        _allOrders.any((o) => o.paymentStatus == OrderPaymentStatus.paid);
    final store = _storeScope.current.value;
    hasCustomizedStore.value = store != null &&
        (store.tagline != null ||
            store.logoUrl != null ||
            store.bannerUrl != null ||
            store.primaryColorHex != null);

    final now = DateTime.now();
    final periodStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: (plan.value?.billingPeriodDays ?? 30) - 1));
    ordersThisPeriod.value =
        _allOrders.where((o) => !o.createdAt.isBefore(periodStart)).length;

    _recomputeRangeMetrics();
    isLoading.value = false;
  }

  void selectRange(DateRangeOption option) {
    selectedRange.value = option;
    if (option != DateRangeOption.custom) customRange.value = null;
    _recomputeRangeMetrics();
  }

  void selectCustomRange(DateTimeRange range) {
    customRange.value = range;
    selectedRange.value = DateRangeOption.custom;
    _recomputeRangeMetrics();
  }

  /// [start] inclusive, [end] exclusive.
  (DateTime, DateTime) _bounds(DateRangeOption option) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final tomorrow = startOfToday.add(const Duration(days: 1));
    switch (option) {
      case DateRangeOption.today:
        return (startOfToday, tomorrow);
      case DateRangeOption.yesterday:
        return (startOfToday.subtract(const Duration(days: 1)), startOfToday);
      case DateRangeOption.last7:
        return (startOfToday.subtract(const Duration(days: 6)), tomorrow);
      case DateRangeOption.last30:
        return (startOfToday.subtract(const Duration(days: 29)), tomorrow);
      case DateRangeOption.last90:
        return (startOfToday.subtract(const Duration(days: 89)), tomorrow);
      case DateRangeOption.thisYear:
        return (DateTime(now.year, 1, 1), tomorrow);
      case DateRangeOption.custom:
        final range = customRange.value;
        if (range == null) return _bounds(DateRangeOption.last30);
        final end = DateTime(range.end.year, range.end.month, range.end.day)
            .add(const Duration(days: 1));
        return (
          DateTime(range.start.year, range.start.month, range.start.day),
          end
        );
    }
  }

  void _recomputeRangeMetrics() {
    final (start, end) = _bounds(selectedRange.value);
    final inRange = _allOrders
        .where((o) => !o.createdAt.isBefore(start) && o.createdAt.isBefore(end))
        .toList();
    final paid = inRange
        .where((o) => o.paymentStatus == OrderPaymentStatus.paid)
        .toList();

    grossSales.value = paid.fold(0.0, (sum, o) => sum + o.total);
    netRevenue.value = paid.fold(0.0, (sum, o) => sum + o.sellerRevenue);
    orderCount.value = inRange.length;
    paidOrderCount.value = paid.length;
    averageOrderValue.value = paid.isEmpty ? 0 : grossSales.value / paid.length;
    cancelledCount.value =
        inRange.where((o) => o.status == OrderStatus.cancelled).length;

    final breakdown = <OrderStatus, int>{
      for (final s in OrderStatus.values) s: 0
    };
    for (final o in inRange) {
      breakdown[o.status] = (breakdown[o.status] ?? 0) + 1;
    }
    statusBreakdown.value = breakdown;

    topProducts.value = _topProducts(paid);
    salesSeries.value = _salesSeries(paid, start, end);

    final periodLength = end.difference(start);
    final prevEnd = start;
    final prevStart = start.subtract(periodLength);
    final previous = _allOrders
        .where((o) =>
            !o.createdAt.isBefore(prevStart) && o.createdAt.isBefore(prevEnd))
        .where((o) => o.paymentStatus == OrderPaymentStatus.paid)
        .toList();
    final prevGross = previous.fold(0.0, (sum, o) => sum + o.total);
    grossSalesDeltaPercent.value = prevGross == 0
        ? null
        : (grossSales.value - prevGross) / prevGross * 100;
    final prevOrderCount = _allOrders
        .where((o) =>
            !o.createdAt.isBefore(prevStart) && o.createdAt.isBefore(prevEnd))
        .length;
    ordersDeltaPercent.value = prevOrderCount == 0
        ? null
        : (orderCount.value - prevOrderCount) / prevOrderCount * 100;
  }

  List<TopProductStat> _topProducts(List<OrderModel> paidOrders) {
    final byProduct = <String, TopProductStat>{};
    for (final order in paidOrders) {
      for (final item in order.items) {
        final existing = byProduct[item.productId];
        byProduct[item.productId] = TopProductStat(
          productId: item.productId,
          title: item.title,
          imageUrl: item.imageUrl,
          quantitySold: (existing?.quantitySold ?? 0) + item.quantity,
          revenue: (existing?.revenue ?? 0) + item.total,
        );
      }
    }
    final list = byProduct.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
    return list.take(5).toList();
  }

  List<SalesPoint> _salesSeries(
      List<OrderModel> paidOrders, DateTime start, DateTime end) {
    // "This year" buckets by month to keep the chart legible; every other
    // range buckets by day.
    final byMonth = selectedRange.value == DateRangeOption.thisYear;
    final buckets = <DateTime, double>{};
    if (byMonth) {
      for (var d = DateTime(start.year, start.month);
          d.isBefore(end);
          d = DateTime(d.year, d.month + 1)) {
        buckets[d] = 0;
      }
    } else {
      for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
        buckets[d] = 0;
      }
    }
    for (final order in paidOrders) {
      final key = byMonth
          ? DateTime(order.createdAt.year, order.createdAt.month)
          : DateTime(
              order.createdAt.year, order.createdAt.month, order.createdAt.day);
      if (buckets.containsKey(key)) {
        buckets[key] = buckets[key]! + order.total;
      }
    }
    final keys = buckets.keys.toList()..sort();
    return keys.map((k) => SalesPoint(k, buckets[k]!)).toList();
  }
}
