import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_metrics.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../data/models/cart_item_model.dart';
import '../../../data/services/currency_service.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../storefront/design/storefront_theme.dart';
import '../../storefront/shell/storefront_links.dart';
import '../../storefront/shell/storefront_page.dart';
import '../../storefront/storefront_session.dart';
import 'cart_controller.dart';

/// `/s/{slug}/cart`: the visitor's cart in the store's theme. Guests can
/// fill it; checkout asks them to sign in.
class CartView extends GetView<CartController> {
  const CartView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = Get.find<StorefrontSession>();
    final cart = controller.cartRepo;
    return StorefrontPage(
      title: l10n.cartTitle,
      slivers: (context, store, design) {
        final style = StoreStyle.of(context);
        final textTheme = Theme.of(context).textTheme;
        return [
          SliverToBoxAdapter(
            child: StorefrontContent(
              maxWidth: 760,
              child: Obx(() {
                // Snapshot inside Obx's tracked scope.
                final items = List.of(cart.items);
                final currency = Get.find<CurrencyService>();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(style.heading(l10n.cartTitle),
                        style: style.headingStyle(textTheme.headlineSmall)),
                    const SizedBox(height: AppSpacing.md),
                    if (items.isEmpty)
                      EmptyState(
                        icon: Icons.shopping_bag_outlined,
                        title: l10n.cartEmptyTitle,
                        message: l10n.cartEmptyMessage,
                        actionLabel: 'Start shopping',
                        onAction: () =>
                            Get.offAllNamed(session.path(StorefrontPaths.shop)),
                      )
                    else ...[
                      for (final item in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _CartLine(item: item),
                        ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                              child: Text('Subtotal',
                                  style: textTheme.titleMedium)),
                          Text(
                              currency.format(cart.subtotal,
                                  fromCode: cart.currency),
                              style: AppTypography.price(
                                  size: 18, color: style.onSurface)),
                        ],
                      ),
                      Text('Shipping and discount codes are added at checkout.',
                          style: textTheme.bodySmall),
                      const SizedBox(height: AppSpacing.md),
                      ElevatedButton(
                        onPressed: () =>
                            Get.toNamed(session.path(StorefrontPaths.checkout)),
                        child: Text(l10n.cartCheckout),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextButton(
                        onPressed: () =>
                            Get.offAllNamed(session.path(StorefrontPaths.shop)),
                        child: const Text('Continue shopping'),
                      ),
                    ],
                  ],
                );
              }),
            ),
          ),
        ];
      },
    );
  }
}

class _CartLine extends GetView<CartController> {
  const _CartLine({required this.item});
  final CartItemModel item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = StoreStyle.of(context);
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final session = Get.find<StorefrontSession>();
    final currency = Get.find<CurrencyService>();
    final cart = controller.cartRepo;
    final thumb = Container(
        width: 72, height: 72, color: scheme.onSurface.withValues(alpha: 0.06));
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: style.panel(),
      child: Row(
        children: [
          InkWell(
            onTap: () => Get.toNamed(
                session.path(StorefrontPaths.product(item.product.id)),
                arguments: item.product),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(style.smallRadius),
              child: item.product.imageUrl.isEmpty
                  ? thumb
                  : CachedNetworkImage(
                      imageUrl: item.product.imageUrl,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => thumb,
                      errorWidget: (_, __, ___) => thumb),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium),
                if (item.selectedVariant case final v?)
                  Text(v.label, style: textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                    currency.format(item.lineTotal,
                        fromCode: item.product.currency),
                    style:
                        AppTypography.price(size: 14, color: style.onSurface)),
              ],
            ),
          ),
          Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Fewer',
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        cart.updateQuantity(item, item.quantity - 1),
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                  ),
                  Text('${item.quantity}'),
                  IconButton(
                    tooltip: 'More',
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        cart.updateQuantity(item, item.quantity + 1),
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => cart.remove(item),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                child: Text(l10n.cartRemove),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
