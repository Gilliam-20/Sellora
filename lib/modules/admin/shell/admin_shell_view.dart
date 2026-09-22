import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/widgets/adaptive_shell_scaffold.dart';
import '../catalog_sync/admin_catalog_sync_view.dart';
import '../dashboard/admin_dashboard_view.dart';
import '../orders/admin_orders_view.dart';
import '../plans/admin_plans_view.dart';
import '../sellers/admin_sellers_view.dart';
import '../stores/admin_stores_view.dart';
import 'admin_shell_controller.dart';

class AdminShellView extends GetView<AdminShellController> {
  const AdminShellView({super.key});

  static const _tabs = [
    AdminDashboardView(),
    AdminSellersView(),
    AdminStoresView(),
    AdminCatalogSyncView(),
    AdminOrdersView(),
    AdminPlansView(),
  ];

  static const _destinations = [
    ShellDestination(icon: Icon(Icons.dashboard_outlined), label: 'Overview'),
    ShellDestination(icon: Icon(Icons.people_alt_outlined), label: 'Sellers'),
    ShellDestination(icon: Icon(Icons.storefront_outlined), label: 'Stores'),
    ShellDestination(icon: Icon(Icons.sync), label: 'Sync'),
    ShellDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
    ShellDestination(icon: Icon(Icons.payments_outlined), label: 'Plans'),
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
