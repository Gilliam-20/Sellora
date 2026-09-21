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
  const ProductCard({super.key, required this.product, required this.onTap});

  final ProductModel product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cloud,
      borderRadius: BorderRadius.circular(AppRadii.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
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
                              style: AppTypography.price(size: 16)),
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
