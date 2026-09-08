import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../data/repositories/cart_repository.dart';
import '../cart/cart_view.dart';
import '../home/buyer_home_view.dart';
import '../orders/buyer_orders_view.dart';
import '../profile/buyer_profile_view.dart';
import 'buyer_shell_controller.dart';

class BuyerShellView extends GetView<BuyerShellController> {
  const BuyerShellView({super.key});

  static const _tabs = [BuyerHomeView(), CartView(), BuyerOrdersView(), BuyerProfileView()];

  @override
  Widget build(BuildContext context) {
    final args = Get.arguments as Map?;
    if (args?['tab'] != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.changeTab(args!['tab'] as int));
    }
    final cart = Get.find<CartRepository>();

    return Obx(
      () => Scaffold(
        body: IndexedStack(index: controller.tabIndex.value, children: _tabs),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: controller.tabIndex.value,
          onTap: controller.changeTab,
          items: [
            const BottomNavigationBarItem(icon: Icon(Icons.storefront_outlined), label: 'Shop'),
            BottomNavigationBarItem(
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
            const BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
            const BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}
