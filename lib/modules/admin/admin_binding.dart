import 'package:get/get.dart';
import 'catalog_sync/admin_catalog_sync_controller.dart';
import 'dashboard/admin_dashboard_controller.dart';
import 'orders/admin_orders_controller.dart';
import 'plans/admin_plans_controller.dart';
import 'sellers/admin_sellers_controller.dart';
import 'shell/admin_shell_controller.dart';

class AdminBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<AdminShellController>(() => AdminShellController());
    Get.lazyPut<AdminDashboardController>(() => AdminDashboardController());
    Get.lazyPut<AdminSellersController>(() => AdminSellersController());
    Get.lazyPut<AdminCatalogSyncController>(() => AdminCatalogSyncController());
    Get.lazyPut<AdminOrdersController>(() => AdminOrdersController());
    Get.lazyPut<AdminPlansController>(() => AdminPlansController());
  }
}
