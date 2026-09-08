import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/product_card.dart';
import 'buyer_home_controller.dart';

class BuyerHomeView extends GetView<BuyerHomeController> {
  const BuyerHomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sellora', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 22, color: AppColors.cargoNavy)),
      ),
      body: RefreshIndicator(
        onRefresh: controller.loadFeed,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
              sliver: SliverToBoxAdapter(
                child: TextField(
                  onSubmitted: controller.search,
                  decoration: const InputDecoration(
                    hintText: 'Search products',
                    prefixIcon: Icon(Icons.search, color: AppColors.slate),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              sliver: SliverToBoxAdapter(
                child: SizedBox(
                  height: 36,
                  child: Obx(
                    () => ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      itemCount: controller.categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        final category = controller.categories[index];
                        final isSelected = controller.selectedCategory.value == category;
                        return ChoiceChip(
                          label: Text(category),
                          selected: isSelected,
                          selectedColor: AppColors.cargoNavy,
                          labelStyle: TextStyle(color: isSelected ? AppColors.cloud : AppColors.ink, fontWeight: FontWeight.w600),
                          onSelected: (_) => controller.selectCategory(category),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            Obx(() {
              if (controller.isLoading.value) {
                return const SliverFillRemaining(child: SelloraLoader());
              }
              if (controller.products.isEmpty) {
                return SliverFillRemaining(
                  child: EmptyState(
                    icon: Icons.search_off,
                    title: 'No products here yet',
                    message: 'Try a different search or category.',
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.md),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                    childAspectRatio: 0.62,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final product = controller.products[index];
                      return ProductCard(
                        product: product,
                        onTap: () => Get.toNamed(Routes.buyerProductDetails, arguments: product),
                      );
                    },
                    childCount: controller.products.length,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
