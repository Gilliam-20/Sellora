import 'package:get/get.dart';
import '../../../data/models/order_model.dart';
import '../../../data/models/store_model.dart';
import '../../../data/models/subscription_plan_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../data/repositories/store_repository.dart';
import '../../../data/repositories/subscription_repository.dart';
import 'admin_dashboard_models.dart';

class AdminDashboardController extends GetxController {
  final AdminRepository _adminRepo = Get.find<AdminRepository>();
  final OrderRepository _orderRepo = Get.find<OrderRepository>();
  final StoreRepository _storeRepo = Get.find<StoreRepository>();
  final SubscriptionRepository _subscriptionRepo =
      Get.find<SubscriptionRepository>();

  final isLoading = true.obs;
  final sellers = <UserModel>[].obs;
  final orders = <OrderModel>[].obs;
  final stores = <StoreModel>[].obs;
  final plans = <SubscriptionPlanModel>[].obs;

  /// Controls the platform chart independently of the headline lifetime
  /// totals. A daily series makes a recent change in marketplace activity
  /// visible instead of burying it in the all-time number.
  final selectedTrendDays = 30.obs;
  final selectedTrendMetric = AdminTrendMetric.gmv.obs;
  final platformTrend = <PlatformTrendPoint>[].obs;

  int get activeSellerCount =>
      sellers.where((s) => s.sellerStatus == SellerStatus.active).length;
  int get pendingSellerCount => sellers
      .where((s) => s.sellerStatus == SellerStatus.pendingApproval)
      .length;
  int get suspendedSellerCount =>
      sellers.where((s) => s.sellerStatus == SellerStatus.suspended).length;
  int get newSellerCount30d => sellers.where((s) {
        final createdAt = s.createdAt;
        return createdAt != null &&
            DateTime.now().difference(createdAt).inDays <= 30;
      }).length;

  List<OrderModel> get _paidOrders =>
      orders.where((o) => o.paymentStatus == OrderPaymentStatus.paid).toList();

  /// Seller GMV — money moving through seller stores. Kept separate from
  /// Sellora's own revenue (see TODO.md section 35: "Do NOT confuse seller
  /// GMV with Sellora revenue").
  double get totalGmv => _paidOrders.fold(0.0, (sum, o) => sum + o.total);

  /// Sellora's 2% cut, snapshotted per order at creation time
  /// (`OrderModel.serviceFeeAmount`). Real against mock data; against the
  /// live backend this is still 0 for every order because the adopted
  /// `createOrder` Cloud Function has no seller/fee concept yet and never
  /// populates the field (see WORKLOG.md, PHASE 8) — this is not a bug in
  /// this dashboard, it's an accurate read of a known upstream gap.
  double get serviceFeeRevenue =>
      _paidOrders.fold(0.0, (sum, o) => sum + o.serviceFeeAmount);

  /// Monthly recurring revenue in KES — every seller with a currently
  /// active subscription, priced at their matched plan's `priceKes`.
  /// KES-only deliberately: there's no currency-conversion service yet
  /// (PHASE 11, not started), and plans themselves are only ever priced in
  /// KES/USD pairs, not the seller's own `currencyCode`.
  double get subscriptionMrr {
    double total = 0;
    for (final seller in sellers) {
      if (!seller.hasActiveSubscription) continue;
      final plan =
          plans.firstWhereOrNull((p) => p.id == seller.subscriptionPlanId);
      if (plan != null) total += plan.priceKes;
    }
    return total;
  }

  double get subscriptionArr => subscriptionMrr * 12;

  /// Total platform revenue — service fees + subscriptions. Excludes seller
  /// GMV, which belongs to sellers, not Sellora.
  double get totalPlatformRevenue => serviceFeeRevenue + subscriptionMrr;

  int ordersWithStatus(OrderStatus status) =>
      orders.where((o) => o.status == status).length;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    final results = await Future.wait([
      _adminRepo.fetchSellers(),
      _orderRepo.allOrders(),
      _storeRepo.allStores(),
      _subscriptionRepo.fetchPlans(),
    ]);
    sellers.value = results[0] as List<UserModel>;
    orders.value = results[1] as List<OrderModel>;
    stores.value = results[2] as List<StoreModel>;
    plans.value = results[3] as List<SubscriptionPlanModel>;
    _recomputePlatformTrend();
    isLoading.value = false;
  }

  void selectTrendDays(int days) {
    selectedTrendDays.value = days;
    _recomputePlatformTrend();
  }

  void selectTrendMetric(AdminTrendMetric metric) {
    selectedTrendMetric.value = metric;
  }

  void _recomputePlatformTrend() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: selectedTrendDays.value - 1));
    final end = today.add(const Duration(days: 1));
    final buckets = <DateTime, ({double gmv, double serviceFees})>{
      for (var day = start; day.isBefore(end); day = day.add(const Duration(days: 1)))
        day: (gmv: 0, serviceFees: 0),
    };

    for (final order in _paidOrders) {
      if (order.createdAt.isBefore(start) || !order.createdAt.isBefore(end)) {
        continue;
      }
      final day = DateTime(
          order.createdAt.year, order.createdAt.month, order.createdAt.day);
      final current = buckets[day];
      if (current != null) {
        buckets[day] = (
          gmv: current.gmv + order.total,
          serviceFees: current.serviceFees + order.serviceFeeAmount,
        );
      }
    }

    platformTrend.value = buckets.entries
        .map((entry) => PlatformTrendPoint(
              day: entry.key,
              gmv: entry.value.gmv,
              serviceFees: entry.value.serviceFees,
            ))
        .toList();
  }
}
