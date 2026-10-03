import 'package:get/get.dart';
import '../../../data/models/order_model.dart';
import '../../../data/models/platform_metrics_model.dart';
import '../../../data/models/store_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../data/repositories/store_repository.dart';
import 'admin_dashboard_models.dart';

class AdminDashboardController extends GetxController {
  final AdminRepository _adminRepo = Get.find<AdminRepository>();
  final OrderRepository _orderRepo = Get.find<OrderRepository>();
  final StoreRepository _storeRepo = Get.find<StoreRepository>();

  final isLoading = true.obs;
  final sellers = <UserModel>[].obs;

  /// The newest orders a client may list (a page, not the whole table):
  /// recent activity and the status queue only. Money figures come from
  /// [metrics], which the server sums over every order.
  final orders = <OrderModel>[].obs;
  final stores = <StoreModel>[].obs;

  final metrics = PlatformMetrics.empty.obs;
  final metricsError = RxnString();
  final isTrendLoading = false.obs;

  /// Controls the platform chart independently of the headline lifetime
  /// totals. A daily series makes a recent change in marketplace activity
  /// visible instead of burying it in the all-time number.
  final selectedTrendDays = 30.obs;
  final selectedTrendMetric = AdminTrendMetric.gmv.obs;

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
  int get suspendedStoreCount => stores.where((s) => s.isSuspended).length;

  /// Seller GMV — money moving through seller stores. Kept separate from
  /// Sellora's own revenue (see TODO.md section 35: "Do NOT confuse seller
  /// GMV with Sellora revenue").
  double get totalGmv => metrics.value.lifetime.gmvKes;

  /// Sellora's 7% cut, snapshotted per order at creation time.
  double get serviceFeeRevenue => metrics.value.lifetime.serviceFeesKes;
  double get refunds => metrics.value.lifetime.refundsKes;
  int get paidOrderCount => metrics.value.lifetime.paidOrders;

  /// Active plans' KES prices, normalized to 30 days.
  double get subscriptionMrr => metrics.value.subscriptions.mrrKes;
  double get subscriptionArr => subscriptionMrr * 12;

  /// Null when no seller has been subscribed in the last 30 days.
  double? get churnRate => metrics.value.subscriptions.churnRate;

  List<PlatformTrendPoint> get platformTrend => [
        for (final day in metrics.value.series)
          PlatformTrendPoint(
              day: day.day, gmv: day.gmvKes, serviceFees: day.serviceFeesKes),
      ];

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
      _loadMetrics(),
    ]);
    sellers.value = results[0] as List<UserModel>;
    orders.value = results[1] as List<OrderModel>;
    stores.value = results[2] as List<StoreModel>;
    isLoading.value = false;
  }

  /// Never throws: a failure (say, the migration that adds the function
  /// isn't applied yet) leaves the rest of the Overview usable.
  Future<void> _loadMetrics() async {
    try {
      metrics.value =
          await _adminRepo.platformMetrics(days: selectedTrendDays.value);
      metricsError.value = null;
    } catch (_) {
      metricsError.value = 'Platform figures couldn\'t be loaded.';
    }
  }

  Future<void> selectTrendDays(int days) async {
    if (days == selectedTrendDays.value) return;
    selectedTrendDays.value = days;
    isTrendLoading.value = true;
    await _loadMetrics();
    isTrendLoading.value = false;
  }

  void selectTrendMetric(AdminTrendMetric metric) {
    selectedTrendMetric.value = metric;
  }
}
