import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              onSubmitted: controller.search,
              decoration: const InputDecoration(hintText: 'Search the catalog', prefixIcon: Icon(Icons.search)),
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
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                itemCount: controller.catalog.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) => _CatalogTile(product: controller.catalog[index]),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _CatalogTile extends StatelessWidget {
  const _CatalogTile({required this.product});
  final ProductModel product;

  @override
  Widget build(BuildContext context) {
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
            child: CachedNetworkImage(imageUrl: product.imageUrl, width: 64, height: 64, fit: BoxFit.cover),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text('CJ cost: ${Formatters.currency(product.costPrice)}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          TextButton(onPressed: () => _showListSheet(context, product), child: const Text('List')),
        ],
      ),
    );
  }

  void _showListSheet(BuildContext context, ProductModel product) {
    final controller = Get.find<SellerCatalogController>();
    final priceCtrl = TextEditingController(text: (product.costPrice * 2.2).toStringAsFixed(2));
    final formKey = GlobalKey<FormState>();

    Get.bottomSheet(
      Container(
        padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom),
        decoration: const BoxDecoration(
          color: AppColors.cloud,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('List "${product.title}"', style: Theme.of(context).textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: AppSpacing.sm),
              Text('CJ cost price: ${Formatters.currency(product.costPrice)}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Your sell price'),
                validator: Validators.price,
              ),
              const SizedBox(height: AppSpacing.lg),
              Obx(
                () => SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: controller.isListing.value
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            final price = double.parse(priceCtrl.text.trim());
                            final success = await controller.listProduct(product, price);
                            Get.back();
                            if (success) {
                              Get.snackbar('Listed', '${product.title} is now live in your store.');
                            }
                          },
                    child: controller.isListing.value
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink))
                        : const Text('Confirm listing'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }
}
