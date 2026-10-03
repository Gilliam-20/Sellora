import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sellora/data/models/order_model.dart';
import 'package:sellora/data/models/platform_metrics_model.dart';
import 'package:sellora/data/repositories/admin_repository.dart';
import 'fakes/mock_admin_repository.dart';
import 'fakes/mock_order_repository.dart';
import 'fakes/mock_store_repository.dart';
import 'package:sellora/data/repositories/order_repository.dart';
import 'package:sellora/data/repositories/store_repository.dart';
import 'package:sellora/modules/admin/dashboard/admin_dashboard_controller.dart';

void main() {
  late MockAdminRepository admin;
  late MockOrderRepository orders;

  setUp(() {
    admin = MockAdminRepository();
    orders = MockOrderRepository();
    Get.put<AdminRepository>(admin);
    Get.put<OrderRepository>(orders);
    Get.put<StoreRepository>(MockStoreRepository());
  });
  tearDown(Get.reset);

  test('money figures come from the server metrics, not the order page',
      () async {
    // A paid order in the client's page must not be summed: the server's
    // KES figures are the only comparable ones across currencies.
    await orders.placeOrder(_order(id: 'o1', total: 99, currency: 'USD'));
    admin.metrics = const PlatformMetrics(
      days: 30,
      lifetime: PlatformTotals(
          gmvKes: 52000, serviceFeesKes: 3640, refundsKes: 1200, paidOrders: 9),
      window: PlatformTotals.zero,
      series: [],
      subscriptions: SubscriptionHealth(active: 3, lapsed30d: 1, mrrKes: 9750),
    );

    final controller = AdminDashboardController();
    await controller.load();

    expect(controller.totalGmv, 52000);
    expect(controller.serviceFeeRevenue, 3640);
    expect(controller.refunds, 1200);
    expect(controller.paidOrderCount, 9);
    expect(controller.subscriptionMrr, 9750);
    expect(controller.subscriptionArr, 9750 * 12);
    expect(controller.churnRate, 0.25);
    expect(controller.metricsError.value, isNull);

    // MockAdminRepository seeds one active and one pending seller.
    expect(controller.activeSellerCount, 1);
    expect(controller.pendingSellerCount, 1);
    expect(controller.suspendedSellerCount, 0);
    expect(controller.stores.length, 2);
    expect(controller.orders.length, 1);
  });

  test('the trend window is asked of the server', () async {
    final controller = AdminDashboardController();
    await controller.load();
    expect(admin.lastMetricsDays, 30);

    admin.metrics = PlatformMetrics(
      days: 7,
      lifetime: PlatformTotals.zero,
      window: PlatformTotals.zero,
      series: [
        PlatformDay(
            day: DateTime(2026, 10, 3),
            gmvKes: 1300,
            serviceFeesKes: 91,
            orders: 1),
      ],
      subscriptions: SubscriptionHealth.zero,
    );
    await controller.selectTrendDays(7);

    expect(admin.lastMetricsDays, 7);
    expect(controller.platformTrend.single.gmv, 1300);
    expect(controller.platformTrend.single.serviceFees, 91);
    expect(controller.churnRate, isNull);
  });

  test('a metrics failure leaves the rest of the overview usable', () async {
    Get.delete<AdminRepository>(force: true);
    Get.put<AdminRepository>(_FailingMetricsRepository());
    final controller = AdminDashboardController();
    await controller.load();

    expect(controller.metricsError.value, isNotNull);
    expect(controller.totalGmv, 0);
    expect(controller.activeSellerCount, 1);
    expect(controller.isLoading.value, isFalse);
  });

  test('PlatformMetrics reads the function result', () {
    final metrics = PlatformMetrics.fromMap({
      'days': 2,
      'currency': 'KES',
      'lifetime': {
        'gmvKes': 1500,
        'serviceFeesKes': 390.5,
        'refundsKes': 200,
        'paidOrders': 2
      },
      'window': {
        'gmvKes': '1500',
        'serviceFeesKes': 0,
        'refundsKes': 0,
        'paidOrders': 2
      },
      'series': [
        {'day': '2026-10-02', 'gmvKes': 0, 'serviceFeesKes': 0, 'orders': 0},
        {
          'day': '2026-10-03',
          'gmvKes': 1500,
          'serviceFeesKes': 390.5,
          'orders': 2
        },
      ],
      'subscriptions': {'active': 0, 'lapsed30d': 0, 'mrrKes': 0},
    });
    expect(metrics.lifetime.serviceFeesKes, 390.5);
    expect(metrics.window.gmvKes, 1500);
    expect(metrics.series.last.day, DateTime(2026, 10, 3));
    expect(metrics.series.last.orders, 2);
    expect(metrics.subscriptions.churnRate, isNull);
  });
}

class _FailingMetricsRepository extends MockAdminRepository {
  @override
  Future<PlatformMetrics> platformMetrics({int days = 30}) =>
      Future.error(Exception('function missing'));
}

OrderModel _order(
    {required String id, required double total, required String currency}) {
  return OrderModel(
    id: id,
    code: id,
    buyerId: 'buyer-1',
    sellerId: 'mock-seller',
    storeId: 'store-aminas',
    items: const [],
    status: OrderStatus.pending,
    total: total,
    currency: currency,
    shippingAddress: ShippingAddress(countryCode: 'KE', line1: '123 St'),
    createdAt: DateTime.now(),
    paymentStatus: OrderPaymentStatus.paid,
  );
}
