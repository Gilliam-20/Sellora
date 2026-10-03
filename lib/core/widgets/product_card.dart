import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_metrics.dart';
import '../../app/theme/app_typography.dart';
import '../../data/models/product_model.dart';
import '../../data/services/currency_service.dart';

/// The storefront product card — the single most-seen component in the
/// buyer experience, so it carries the most visual weight: soft rounded
/// corners, generous image, price treatment as a first-class element
/// rather than small grey text.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.style = const ProductCardStyle(),
  });

  final ProductModel product;
  final VoidCallback onTap;

  /// A storefront theme's card treatment; Meridian's by default.
  final ProductCardStyle style;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: style.color,
      elevation: style.elevation,
      shadowColor: const Color(0x33000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(style.radius),
        side: style.border,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The photo takes what the text leaves, so a long title can't
            // overflow the tile; the grid sizes tiles for the photo shape
            // (ProductCardStyle.tileAspectRatio).
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: product.imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: AppColors.mist),
                    errorWidget: (_, __, ___) => Container(
                      color: AppColors.mist,
                      child: const Icon(Icons.inventory_2_outlined,
                          color: AppColors.slateLight),
                    ),
                  ),
                  if (product.discountPercent != null &&
                      product.discountPercent! > 0)
                    Positioned(
                      top: AppSpacing.sm,
                      left: AppSpacing.sm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.manifestGold,
                          borderRadius: BorderRadius.circular(AppRadii.control),
                        ),
                        child: Text(
                          '-${product.discountPercent}%',
                          style: AppTypography.textTheme.labelSmall?.copyWith(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm + 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 6),
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
                              style: AppTypography.price(
                                  size: 16, color: style.foreground)),
                        ),
                        if (product.compareAtPrice != null) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              currency.format(product.compareAtPrice!,
                                  fromCode: product.currency),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      decoration: TextDecoration.lineThrough),
                            ),
                          ),
                        ],
                      ],
                    );
                  }),
                  if (product.soldCount > 0) ...[
                    const SizedBox(height: 2),
                    Text('${product.soldCount} sold',
                        style: Theme.of(context).textTheme.labelSmall),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How a [ProductCard] looks. A storefront theme sets its own
/// (`StoreStyle.productCard`); the default is Meridian's soft card.
class ProductCardStyle {
  const ProductCardStyle({
    this.color = AppColors.cloud,
    this.foreground,
    this.radius = AppRadii.card,
    this.border = BorderSide.none,
    this.elevation = 0,
    this.imageAspectRatio = 1,
  });

  final Color color;

  /// The price color; Ink when null.
  final Color? foreground;
  final double radius;
  final BorderSide border;
  final double elevation;

  /// Photo width / height, roughly: the grid tile is sized for it, and the
  /// photo fills whatever the text below it leaves.
  final double imageAspectRatio;

  /// The grid tile's width / height for this photo shape: the photo plus
  /// about 0.61 of the tile's width for title, price and sales (0.62
  /// overall for a square photo, the grid's long-standing ratio).
  double get tileAspectRatio => 1 / (1 / imageAspectRatio + 0.61);
}
