import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../catalog_sync/admin_catalog_sync_view.dart';
import '../dashboard/admin_dashboard_view.dart';
import '../orders/admin_orders_view.dart';
import '../plans/admin_plans_view.dart';
import '../sellers/admin_sellers_view.dart';
import 'admin_shell_controller.dart';

class AdminShellView extends GetView<AdminShellController> {
  const AdminShellView({super.key});

  static const _tabs = [
    AdminDashboardView(),
    AdminSellersView(),
    AdminCatalogSyncView(),
    AdminOrdersView(),
    AdminPlansView(),
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
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'Overview'),
            BottomNavigationBarItem(icon: Icon(Icons.storefront_outlined), label: 'Sellers'),
            BottomNavigationBarItem(icon: Icon(Icons.sync), label: 'Sync'),
            BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
            BottomNavigationBarItem(icon: Icon(Icons.payments_outlined), label: 'Plans'),
          ],
        ),
      ),
    );
  }
}
