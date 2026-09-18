import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/routes/app_routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_metrics.dart';
import '../../core/utils/color_utils.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/product_card.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';
import 'storefront_controller.dart';

/// Guest-accessible storefront for a single tenant. Cart and checkout are
/// intentionally not attached until their store-bound data model is ready.
class StorefrontView extends GetView<StorefrontController> {
  const StorefrontView({super.key});

  @override
  Widget build(BuildContext context) {
    final sliverPadding = centeredSliverPadding(context);
    return Scaffold(
      appBar: AppBar(
        title:
            Obx(() => Text(controller.scope.current.value?.name ?? 'Sellora')),
        leading: Obx(() {
          final logoUrl = controller.scope.current.value?.logoUrl;
          if (logoUrl == null || logoUrl.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: CircleAvatar(
              backgroundImage: CachedNetworkImageProvider(logoUrl),
              backgroundColor: AppColors.mist,
            ),
          );
        }),
        actions: [
          Obx(() {
            final store = controller.scope.current.value;
            if (store == null) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: 'Account',
              onPressed: () {
                final user = Get.find<AuthRepository>().cachedUser;
                final signedInHere =
                    user != null && user.role == UserRole.buyer && user.storeId == store.id;
                Get.toNamed(signedInHere
                    ? Routes.buyerShell
                    : '/s/${store.slug}/login');
              },
            );
          }),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.load,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                sliverPadding.horizontal / 2,
                AppSpacing.md,
                sliverPadding.horizontal / 2,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Obx(() {
                  final bannerUrl = controller.scope.current.value?.bannerUrl;
                  if (bannerUrl == null || bannerUrl.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    child: CachedNetworkImage(
                      imageUrl: bannerUrl,
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(height: 140, color: AppColors.mist),
                      errorWidget: (_, __, ___) =>
                          Container(height: 140, color: AppColors.mist),
                    ),
                  );
                }),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                sliverPadding.horizontal / 2,
                AppSpacing.md,
                sliverPadding.horizontal / 2,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Obx(() {
                  final store = controller.scope.current.value;
                  return AppPageHeader(
                    title: store?.name ?? 'Storefront',
                    subtitle: store?.tagline ?? 'Products selected for you.',
                  );
                }),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                sliverPadding.horizontal / 2,
                AppSpacing.md,
                sliverPadding.horizontal / 2,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: AppSearchField(
                  hintText: 'Search this store',
                  onChanged: controller.search,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              sliver: SliverToBoxAdapter(
                child: SizedBox(
                  height: 36,
                  child: Obx(() => ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.symmetric(
                          horizontal: sliverPadding.horizontal / 2,
                        ),
                        itemCount: controller.categories.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final category = controller.categories[index];
                          final selected =
                              controller.selectedCategory.value == category;
                          final accent = hexToColor(
                                  controller.scope.current.value?.primaryColorHex) ??
                              AppColors.cargoNavy;
                          return ChoiceChip(
                            label: Text(category),
                            selected: selected,
                            selectedColor: accent,
                            labelStyle: TextStyle(
                              color: selected ? AppColors.cloud : AppColors.ink,
                              fontWeight: FontWeight.w600,
                            ),
                            onSelected: (_) =>
                                controller.selectCategory(category),
                          );
                        },
                      )),
                ),
              ),
            ),
            Obx(() {
              if (controller.isLoading.value) {
                return const SliverFillRemaining(child: AppLoadingState());
              }
              if (controller.scope.errorMessage.value != null) {
                return SliverFillRemaining(
                  child: AppErrorState(
                    message: controller.scope.errorMessage.value!,
                    onRetry: controller.load,
                  ),
                );
              }
              if (controller.items.isEmpty) {
                return const SliverFillRemaining(
                  child: EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'No products are published yet',
                    message:
                        'Check back soon for this store’s latest collection.',
                  ),
                );
              }
              return SliverPadding(
                padding: sliverPadding,
                sliver: SliverGrid(
                  gridDelegate: productGridDelegate(),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => ProductCard(
                      product: controller.items[index],
                      onTap: () {},
                    ),
                    childCount: controller.items.length,
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
