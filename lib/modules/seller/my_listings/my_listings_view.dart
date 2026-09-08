import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import 'my_listings_controller.dart';

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
            message: 'List products from the CJ Dropshipping catalog to start selling.',
          );
        }
        return RefreshIndicator(
          onRefresh: controller.load,
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: controller.listings.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final product = controller.listings[index];
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
                      child: CachedNetworkImage(imageUrl: product.imageUrl, width: 56, height: 56, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(Formatters.currency(product.sellPrice), style: AppTypography.price(size: 14)),
                              const SizedBox(width: 8),
                              Text('margin ${product.marginPercent.toStringAsFixed(0)}%', style: Theme.of(context).textTheme.labelSmall),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: product.isListed,
                      activeColor: AppColors.horizonTeal,
                      onChanged: (_) => controller.unlist(product.id),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      }),
    );
  }
}
