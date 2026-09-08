import 'package:flutter/material.dart';
import 'package:get/get.dart';
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

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Scaffold(
        body: IndexedStack(index: controller.tabIndex.value, children: _tabs),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: controller.tabIndex.value,
          onTap: controller.changeTab,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
            BottomNavigationBarItem(icon: Icon(Icons.travel_explore_outlined), label: 'Catalog'),
            BottomNavigationBarItem(icon: Icon(Icons.storefront_outlined), label: 'Listings'),
            BottomNavigationBarItem(icon: Icon(Icons.local_shipping_outlined), label: 'Orders'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}
