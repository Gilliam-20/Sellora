import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_metrics.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/widgets/app_page.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/store_page.dart';
import '../../../data/services/currency_service.dart';
import '../../storefront/design/storefront_theme.dart';
import '../../storefront/shell/storefront_links.dart';
import '../../storefront/shell/storefront_page.dart';
import 'product_details_controller.dart';

/// A product page in the store's theme: photos, price, options, quantity,
/// add to cart / buy now, the description, and links to the store's
/// shipping and refund policies when it has them.
class ProductDetailsView extends GetView<ProductDetailsController> {
  const ProductDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() => StorefrontPage(
          title: controller.product.value?.title,
          slivers: (context, store, design) => [
            SliverToBoxAdapter(
              child: StorefrontContent(
                child: Obx(() {
                  if (controller.isLoading.value) {
                    return const SizedBox(
                        height: 320, child: AppLoadingState());
                  }
                  final product = controller.product.value;
                  if (product == null) {
                    return EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: 'This product isn\'t available',
                      message: 'It may have sold out or been removed.',
                      actionLabel: 'Keep shopping',
                      onAction: () => Get.offAllNamed(
                          controller.session.path(StorefrontPaths.shop)),
                    );
                  }
                  return LayoutBuilder(builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 760;
                    final gallery = _Gallery(controller: controller);
                    final info = _Info(product: product);
                    if (!wide) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          gallery,
                          const SizedBox(height: AppSpacing.lg),
                          info,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: gallery),
                        const SizedBox(width: AppSpacing.xl),
                        Expanded(child: info),
                      ],
                    );
                  });
                }),
              ),
            ),
          ],
        ));
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery({required this.controller});
  final ProductDetailsController controller;

  @override
  Widget build(BuildContext context) {
    final style = StoreStyle.of(context);
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(style.largeRadius);
    final placeholder = ColoredBox(
        color: scheme.onSurface.withValues(alpha: 0.06),
        child: Icon(Icons.inventory_2_outlined,
            color: scheme.onSurface.withValues(alpha: 0.4)));
    Widget image(String url) => url.isEmpty
        ? placeholder
        : CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (_, __) => placeholder,
            errorWidget: (_, __, ___) => placeholder);

    return Obx(() {
      final current = controller.previewImage.value;
      final gallery = controller.gallery;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: radius,
            child: AspectRatio(aspectRatio: 1, child: image(current)),
          ),
          if (gallery.length > 1) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: gallery.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.xs),
                itemBuilder: (context, i) {
                  final url = gallery[i];
                  return InkWell(
                    onTap: () => controller.previewImage.value = url,
                    child: Container(
                      width: 64,
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: url == current
                                ? scheme.primary
                                : Colors.transparent,
                            width: 2),
                        borderRadius:
                            BorderRadius.circular(style.smallRadius + 2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(style.smallRadius),
                        child: image(url),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      );
    });
  }
}

class _Info extends GetView<ProductDetailsController> {
  const _Info({required this.product});
  final ProductModel product;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final session = controller.session;
    final currency = Get.find<CurrencyService>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(product.title, style: textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        Obx(() => Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: AppSpacing.sm,
              children: [
                Text(
                    currency.format(product.sellPrice,
                        fromCode: product.currency),
                    style:
                        AppTypography.price(size: 22, color: scheme.onSurface)),
                if (product.compareAtPrice != null)
                  Text(
                      currency.format(product.compareAtPrice!,
                          fromCode: product.currency),
                      style: textTheme.bodyMedium
                          ?.copyWith(decoration: TextDecoration.lineThrough)),
              ],
            )),
        if (product.soldCount > 0) ...[
          const SizedBox(height: AppSpacing.xs),
          Text('${product.soldCount} sold', style: textTheme.bodySmall),
        ],
        Text('Shipping is calculated at checkout.', style: textTheme.bodySmall),
        if (product.visibleVariants.length > 1) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Choose an option', style: textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Obx(() => Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final v in product.visibleVariants)
                    ChoiceChip(
                      label: Text(v.label),
                      selected: controller.selectedVariant.value?.vid == v.vid,
                      selectedColor: scheme.primary,
                      labelStyle: TextStyle(
                          color: controller.selectedVariant.value?.vid == v.vid
                              ? scheme.onPrimary
                              : scheme.onSurface),
                      onSelected: (_) => controller.selectVariant(v),
                    ),
                ],
              )),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Text('Quantity', style: textTheme.titleSmall),
            const SizedBox(width: AppSpacing.md),
            Container(
              decoration: BoxDecoration(
                border:
                    Border.all(color: scheme.onSurface.withValues(alpha: 0.2)),
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                      tooltip: 'Fewer',
                      onPressed: controller.decrement,
                      icon: const Icon(Icons.remove, size: 18)),
                  Obx(() => Text('${controller.quantity.value}',
                      style: textTheme.titleSmall)),
                  IconButton(
                      tooltip: 'More',
                      onPressed: controller.increment,
                      icon: const Icon(Icons.add, size: 18)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              controller.addToCart();
              Get.snackbar('Added to cart',
                  '${product.title} · qty ${controller.quantity.value}',
                  mainButton: TextButton(
                    onPressed: () =>
                        Get.toNamed(session.path(StorefrontPaths.cart)),
                    child: const Text('View cart'),
                  ));
            },
            child: const Text('Add to cart'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: controller.buyNow,
            child: const Text('Buy now'),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Description', style: textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          product.description.isEmpty
              ? 'No description provided for this product.'
              : product.description,
          style: textTheme.bodyMedium,
        ),
        Obx(() {
          final pages = session.pages;
          final links = [
            for (final kind in const [
              StorePageKind.shipping,
              StorePageKind.refund
            ])
              if (pages[kind] case final page?) (kind, page.title),
          ];
          if (links.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Wrap(
              spacing: AppSpacing.xs,
              children: [
                for (final (kind, title) in links)
                  TextButton.icon(
                    onPressed: () =>
                        Get.toNamed(session.path(StorefrontPaths.page(kind))),
                    icon: const Icon(Icons.info_outline, size: 16),
                    label: Text(title),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
