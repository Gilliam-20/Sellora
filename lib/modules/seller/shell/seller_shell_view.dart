import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/widgets/adaptive_shell_scaffold.dart';
import '../catalog/seller_catalog_view.dart';
import '../dashboard/seller_dashboard_view.dart';
import '../my_listings/my_listings_view.dart';
import '../orders/seller_orders_view.dart';
import '../profile/seller_profile_view.dart';
import 'seller_shell_controller.dart';

class SellerShellView extends GetView<SellerShellController> {
  const SellerShellView({super.key});

  static const _tabs = [
    SellerDashboardView(),
    SellerCatalogView(),
    MyListingsView(),
    SellerOrdersView(),
    SellerProfileView(),
  ];

  static const _destinations = [
    ShellDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
    ShellDestination(
        icon: Icon(Icons.travel_explore_outlined), label: 'Catalog'),
    ShellDestination(icon: Icon(Icons.storefront_outlined), label: 'Listings'),
    ShellDestination(
        icon: Icon(Icons.local_shipping_outlined), label: 'Orders'),
    ShellDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => AdaptiveShellScaffold(
        currentIndex: controller.tabIndex.value,
        onDestinationSelected: controller.changeTab,
        tabs: _tabs,
        destinations: _destinations,
      ),
    );
  }
}
