import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/common.dart';
import '../../../data/models/product_model.dart';
import '../../../data/repositories/cart_repository.dart';
import '../../../data/services/currency_service.dart';
import 'product_details_controller.dart';

class ProductDetailsView extends GetView<ProductDetailsController> {
  const ProductDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    final product = controller.product;
    final cart = Get.find<CartRepository>();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 340,
            backgroundColor: AppColors.mist,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              background: Obx(() => CachedNetworkImage(
                  imageUrl: controller.previewImage.value.isNotEmpty
                      ? controller.previewImage.value
                      : product.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: AppColors.mist),
                  errorWidget: (_, __, ___) => Container(
                      color: AppColors.mist,
                      child: const Icon(Icons.inventory_2_outlined,
                          color: AppColors.slateLight)))),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  centeredSliverPadding(context, minHorizontal: AppSpacing.lg)
                      .add(const EdgeInsets.symmetric(vertical: AppSpacing.lg)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.title,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.sm),
                  Obx(() {
                    final currency = Get.find<CurrencyService>();
                    return Row(
                      children: [
                        Flexible(
                          child: Text(
                              currency.format(product.sellPrice,
                                  fromCode: product.currency),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.price(size: 22)),
                        ),
                        if (product.compareAtPrice != null) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              currency.format(product.compareAtPrice!,
                                  fromCode: product.currency),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                      decoration: TextDecoration.lineThrough),
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (product.rating > 0) ...[
                          const Icon(Icons.star,
                              size: 16, color: AppColors.manifestGoldDeep),
                          const SizedBox(width: 2),
                          Text(product.rating.toStringAsFixed(1)),
                        ],
                      ],
                    );
                  }),
                  if (product.soldCount > 0) ...[
                    const SizedBox(height: 4),
                    Text('${product.soldCount} sold',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  const Divider(),
                  const SizedBox(height: AppSpacing.md),
                  Text('Description',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    product.description.isEmpty
                        ? 'No description provided for this product.'
                        : product.description,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (product.visibleVariants.length > 1) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text('Choose an option',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Obx(() => _BuyerVariantPicker(
                          variants: product.visibleVariants,
                          selected: controller.selectedVariant.value,
                          onSelect: controller.selectVariant,
                        )),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Text('Quantity',
                          style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
                      _QuantityStepper(),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        label: 'Add to cart',
        onPressed: () {
          controller.addToCart();
          Get.back();
        },
      ),
      floatingActionButton: Obx(
        () => cart.itemCount > 0
            ? FloatingActionButton.extended(
                backgroundColor: AppColors.horizonTeal,
                foregroundColor: AppColors.ink,
                onPressed: () =>
                    Get.toNamed('/s/${Get.parameters['slug']}/checkout'),
                icon: const Icon(Icons.shopping_bag_outlined),
                label: Text('${cart.itemCount}'),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

class _BuyerVariantPicker extends StatelessWidget {
  const _BuyerVariantPicker({
    required this.variants,
    required this.selected,
    required this.onSelect,
  });

  final List<ProductVariant> variants;
  final ProductVariant? selected;
  final ValueChanged<ProductVariant> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: variants.map((variant) {
        final isSelected = selected?.vid == variant.vid;
        return ChoiceChip(
          label: Text(variant.label),
          selected: isSelected,
          selectedColor: AppColors.manifestGold.withValues(alpha: 0.3),
          onSelected: (_) => onSelect(variant),
        );
      }).toList(),
    );
  }
}

class _QuantityStepper extends GetView<ProductDetailsController> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          border: Border.all(color: AppColors.hairline),
          borderRadius: BorderRadius.circular(AppRadii.control)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
              onPressed: controller.decrement,
              icon: const Icon(Icons.remove, size: 18)),
          Obx(() => Text('${controller.quantity.value}',
              style: Theme.of(context).textTheme.titleSmall)),
          IconButton(
              onPressed: controller.increment,
              icon: const Icon(Icons.add, size: 18)),
        ],
      ),
    );
  }
}
