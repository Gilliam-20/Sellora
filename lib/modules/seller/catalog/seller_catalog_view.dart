import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../data/models/product_model.dart';
import 'seller_catalog_controller.dart';

class SellerCatalogView extends GetView<SellerCatalogController> {
  const SellerCatalogView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CJ Dropshipping catalog')),
      body: ResponsiveCenter(
        maxWidth: 720,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: context.pageHorizontalPadding,
                  vertical: AppSpacing.md),
              child: TextField(
                onSubmitted: controller.search,
                decoration: const InputDecoration(
                    hintText: 'Search the catalog',
                    prefixIcon: Icon(Icons.search)),
              ),
            ),
            Expanded(
              child: Obx(() {
                if (controller.isLoading.value) return const SelloraLoader();
                if (controller.catalog.isEmpty) {
                  return const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'No matching products',
                    message: 'Try another search term.',
                  );
                }
                return ListView.separated(
                  padding: EdgeInsets.symmetric(
                      horizontal: context.pageHorizontalPadding),
                  itemCount: controller.catalog.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) =>
                      _CatalogTile(product: controller.catalog[index]),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogTile extends StatelessWidget {
  const _CatalogTile({required this.product});
  final ProductModel product;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cloud,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: () => Get.toNamed(Routes.sellerProductImport, arguments: product),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.stub),
                child: CachedNetworkImage(
                    imageUrl: product.imageUrl,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Text(
                        'CJ cost: ${Formatters.currency(product.costPrice, code: product.currency)}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.slate),
            ],
          ),
        ),
      ),
    );
  }
}
