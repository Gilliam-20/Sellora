import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import 'my_listings_controller.dart';

enum _ListingAction { publish, pause }

class MyListingsView extends GetView<MyListingsController> {
  const MyListingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My listings')),
      body: Obx(() {
        if (controller.isLoading.value) return const SelloraLoader();
        if (controller.listings.isEmpty) {
          return const EmptyState(
            icon: Icons.storefront_outlined,
            title: 'Nothing listed yet',
            message:
                'List products from the CJ Dropshipping catalog to start selling.',
          );
        }
        return RefreshIndicator(
          onRefresh: controller.load,
          child: ResponsiveCenter(
            maxWidth: 720,
            child: ListView.separated(
              padding: EdgeInsets.symmetric(
                horizontal: context.pageHorizontalPadding,
                vertical: AppSpacing.md,
              ),
              itemCount: controller.listings.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final product = controller.listings[index];
                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.cloud,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    onTap: () => Get.toNamed(
                      Routes.sellerManageVariants,
                      arguments: product,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadii.stub),
                            child: CachedNetworkImage(
                              imageUrl: product.imageUrl,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                width: 56,
                                height: 56,
                                color: AppColors.mist,
                              ),
                              errorWidget: (_, __, ___) => Container(
                                width: 56,
                                height: 56,
                                color: AppColors.mist,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      Formatters.currency(product.sellPrice),
                                      style: AppTypography.price(size: 14),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'margin ${product.marginPercent.toStringAsFixed(0)}%',
                                      style: Theme.of(context).textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                                if (product.variants.length > 1) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    '${product.variants.length} variants · tap to manage',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: AppColors.slate),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _ListingStatusBadge(isListed: product.isListed),
                              const SizedBox(height: 2),
                              PopupMenuButton<_ListingAction>(
                                tooltip: 'Listing actions',
                                icon: const Icon(Icons.more_horiz),
                                onSelected: (action) {
                                  if (action == _ListingAction.publish) {
                                    controller.relist(product.id);
                                  } else {
                                    controller.unlist(product.id);
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: product.isListed
                                        ? _ListingAction.pause
                                        : _ListingAction.publish,
                                    child: Row(
                                      children: [
                                        Icon(
                                          product.isListed
                                              ? Icons.pause_circle_outline
                                              : Icons.publish_outlined,
                                        ),
                                        const SizedBox(width: AppSpacing.sm),
                                        Text(
                                          product.isListed
                                              ? 'Pause listing'
                                              : 'Publish listing',
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      }),
    );
  }
}

class _ListingStatusBadge extends StatelessWidget {
  const _ListingStatusBadge({required this.isListed});

  final bool isListed;

  @override
  Widget build(BuildContext context) {
    final color = isListed ? AppColors.horizonTeal : AppColors.slate;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Text(
        isListed ? 'Live' : 'Paused',
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
