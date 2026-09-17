import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/adaptive_shell_scaffold.dart';
import '../../../data/repositories/cart_repository.dart';
import '../cart/cart_view.dart';
import '../home/buyer_home_view.dart';
import '../orders/buyer_orders_view.dart';
import '../profile/buyer_profile_view.dart';
import '../../notifications/notification_center.dart';
import '../../notifications/notifications_view.dart';
import 'buyer_shell_controller.dart';

class BuyerShellView extends GetView<BuyerShellController> {
  const BuyerShellView({super.key});

  static const _tabs = [
    BuyerHomeView(),
    CartView(),
    BuyerOrdersView(),
    NotificationsView(),
    BuyerProfileView()
  ];

  @override
  Widget build(BuildContext context) {
    final cart = Get.find<CartRepository>();
    final notifications = Get.find<NotificationCenter>();

    return Obx(
      () => AdaptiveShellScaffold(
        currentIndex: controller.tabIndex.value,
        onDestinationSelected: controller.changeTab,
        tabs: _tabs,
        destinations: [
          const ShellDestination(
              icon: Icon(Icons.storefront_outlined), label: 'Shop'),
          ShellDestination(
            icon: Obx(
              () => Badge(
                isLabelVisible: cart.itemCount > 0,
                label: Text('${cart.itemCount}'),
                backgroundColor: AppColors.manifestGold,
                textColor: AppColors.ink,
                child: const Icon(Icons.shopping_bag_outlined),
              ),
            ),
            label: 'Cart',
          ),
          const ShellDestination(
              icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
          ShellDestination(
            icon: Obx(
              () => Badge(
                isLabelVisible: notifications.unreadCount > 0,
                label: Text('${notifications.unreadCount}'),
                child: const Icon(Icons.notifications_outlined),
              ),
            ),
            label: 'Alerts',
          ),
          const ShellDestination(
              icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}
