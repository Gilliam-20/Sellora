import 'package:get/get.dart';
import 'catalog/seller_catalog_controller.dart';
import 'dashboard/seller_dashboard_controller.dart';
import 'my_listings/my_listings_controller.dart';
import 'orders/seller_orders_controller.dart';
import 'shell/seller_shell_controller.dart';
import 'subscription/seller_subscription_controller.dart';

class SellerBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SellerShellController>(() => SellerShellController());
    Get.lazyPut<SellerDashboardController>(() => SellerDashboardController());
    Get.lazyPut<SellerCatalogController>(() => SellerCatalogController());
    Get.lazyPut<MyListingsController>(() => MyListingsController());
    Get.lazyPut<SellerOrdersController>(() => SellerOrdersController());
  }
}

class SellerSubscriptionBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SellerSubscriptionController>(
        () => SellerSubscriptionController());
  }
}
