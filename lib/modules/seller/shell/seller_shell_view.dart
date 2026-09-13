import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/widgets/adaptive_shell_scaffold.dart';
import '../../../core/widgets/app_page.dart';
import '../../../core/widgets/empty_state.dart';
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
    return Obx(() {
      final scope = controller.scope;
      // Product/order screens below read from the store the seller owns —
      // don't let them interact with a shell whose store is still resolving
      // or failed to resolve at all (see WORKLOG.md's "Gap found, not
      // fixed" entry: a seller can, in principle, have no store yet).
      if (scope.current.value == null) {
        if (scope.isResolving.value) {
          return const Scaffold(
              body: AppLoadingState(label: 'Loading your store…'));
        }
        return Scaffold(
          body: Column(
            children: [
              Expanded(
                child: EmptyState(
                  icon: Icons.storefront_outlined,
                  title: 'We couldn\'t load your store',
                  message: scope.errorMessage.value ??
                      'Something went wrong loading your store.',
                  actionLabel: 'Try again',
                  onAction: controller.resolveStore,
                ),
              ),
              TextButton(
                onPressed: controller.signOut,
                child: const Text('Sign out'),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        );
      }
      return AdaptiveShellScaffold(
        currentIndex: controller.tabIndex.value,
        onDestinationSelected: controller.changeTab,
        tabs: _tabs,
        destinations: _destinations,
      );
    });
  }
}
