import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../data/models/store_model.dart';
import '../controllers/store_select_controller.dart';

/// A buyer registers as a customer of one specific store rather than a
/// global Sellora account — this is the demo-mode stand-in for landing
/// on that store's own URL, until path routing (`/s/:slug`) exists.
class StoreSelectView extends GetView<StoreSelectController> {
  const StoreSelectView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a store')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
              horizontal: context.pageHorizontalPadding,
              vertical: AppSpacing.lg),
          child: ResponsiveCenter(
            maxWidth: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Shop a Sellora store',
                    style: Theme.of(context).textTheme.displaySmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Every seller on Sellora runs their own store. Pick one to create your account there.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                Obx(() {
                  if (controller.isLoading.value) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                      child: SelloraLoader(),
                    );
                  }
                  if (controller.stores.isEmpty) {
                    return const EmptyState(
                      icon: Icons.storefront_outlined,
                      title: 'No stores yet',
                      message:
                          'Check back once a seller has opened their store.',
                    );
                  }
                  return Column(
                    children: controller.stores
                        .map(
                          (store) => Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.md),
                            child: _StoreCard(
                              store: store,
                              onTap: () => Get.toNamed(
                                Routes.registerBuyer,
                                arguments: {
                                  'storeId': store.id,
                                  'storeSlug': store.slug,
                                  'storeName': store.name
                                },
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.store, required this.onTap});

  final StoreModel store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cloud,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.hairline),
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm + 2),
                decoration: BoxDecoration(
                    color: AppColors.buyerAccent.withValues(alpha: 0.15),
                    shape: BoxShape.circle),
                child: const Icon(Icons.storefront_outlined,
                    color: AppColors.buyerAccent),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(store.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    if (store.tagline != null) ...[
                      const SizedBox(height: 4),
                      Text(store.tagline!,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.slateLight),
            ],
          ),
        ),
      ),
    );
  }
}
