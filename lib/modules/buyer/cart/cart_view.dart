import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../data/services/currency_service.dart';
import 'cart_controller.dart';

class CartView extends GetView<CartController> {
  const CartView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your cart')),
      body: Obx(() {
        // Snapshot the RxList inside Obx's tracked scope — ListView's
        // itemBuilder runs later during layout, outside that scope, so
        // indexing the RxList directly there would read the observable
        // where GetX can no longer see it (see StorefrontView/BuyerOrdersView).
        final items = List.of(controller.cartRepo.items);
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.shopping_bag_outlined,
            title: 'Your cart is empty',
            message: 'Products you add will show up here.',
          );
        }
        return ResponsiveCenter(
          maxWidth: 720,
          child: ListView.separated(
            padding: EdgeInsets.symmetric(
                horizontal: context.pageHorizontalPadding,
                vertical: AppSpacing.md),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final item = items[index];
              return Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.cloud,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.stub),
                      child: CachedNetworkImage(
                          imageUrl: item.product.imageUrl,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.product.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium),
                          const SizedBox(height: 4),
                          Obx(() => Text(
                              Get.find<CurrencyService>().format(
                                  item.product.sellPrice,
                                  fromCode: item.product.currency),
                              style: AppTypography.price(size: 14))),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () => controller.cartRepo
                                  .updateQuantity(
                                      item.product.id, item.quantity - 1),
                              icon: const Icon(Icons.remove_circle_outline,
                                  size: 20),
                            ),
                            Text('${item.quantity}'),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () => controller.cartRepo
                                  .updateQuantity(
                                      item.product.id, item.quantity + 1),
                              icon: const Icon(Icons.add_circle_outline,
                                  size: 20),
                            ),
                          ],
                        ),
                        TextButton(
                          onPressed: () =>
                              controller.cartRepo.remove(item.product.id),
                          style: TextButton.styleFrom(
                              foregroundColor: AppColors.danger,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 32)),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      }),
      bottomNavigationBar: Obx(() {
        if (controller.cartRepo.items.isEmpty) return const SizedBox.shrink();
        return BottomActionBar(
          label: 'Checkout',
          trailingText: Get.find<CurrencyService>().format(
              controller.cartRepo.subtotal,
              fromCode: controller.cartRepo.currency),
          onPressed: () => Get.toNamed('/s/${Get.parameters['slug']}/checkout'),
        );
      }),
    );
  }
}
