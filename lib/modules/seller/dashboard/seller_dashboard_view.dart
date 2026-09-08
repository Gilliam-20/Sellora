import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/manifest_stub.dart';
import 'seller_dashboard_controller.dart';

class SellerDashboardView extends GetView<SellerDashboardController> {
  const SellerDashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final user = controller.authRepo.cachedUser;

    return Scaffold(
      appBar: AppBar(title: Text(user?.storeName ?? 'Dashboard')),
      body: Obx(() {
        if (controller.isLoading.value) return const SelloraLoader();
        return RefreshIndicator(
          onRefresh: controller.load,
          child: ResponsiveCenter(
            maxWidth: 900,
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: context.pageHorizontalPadding, vertical: AppSpacing.md),
              children: [
                Text('Welcome back', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 22)),
                const SizedBox(height: 4),
                Text(
                  user?.hasActiveSubscription == true
                      ? 'Your subscription renews ${Formatters.date(user!.subscriptionActiveUntil!)}.'
                      : 'Your subscription needs attention.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                GridView.extent(
                  // A fixed 2-column count stayed 2-up all the way to a
                  // desktop window; an extent-based grid grows toward 4
                  // stat tiles per row as the viewport widens instead.
                  maxCrossAxisExtent: 260,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: AppSpacing.sm,
                  mainAxisSpacing: AppSpacing.sm,
                  childAspectRatio: 1.5,
                  children: [
                    ManifestStatCard(label: 'Revenue', value: Formatters.currency(controller.totalRevenue.value, code: 'KES'), accentColor: AppColors.manifestGold),
                    ManifestStatCard(label: 'Active listings', value: '${controller.listingCount.value}', accentColor: AppColors.horizonTeal),
                    ManifestStatCard(label: 'Orders to fulfill', value: '${controller.pendingCount.value}', accentColor: AppColors.info),
                    GestureDetector(
                      onTap: () => Get.toNamed(Routes.sellerSubscription),
                      child: ManifestStatCard(label: 'Plan', value: user?.subscriptionPlanId?.capitalizeFirst ?? '—', accentColor: AppColors.adminAccent),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                const SectionHeader(title: 'Recent orders'),
                const SizedBox(height: AppSpacing.sm),
                if (controller.recentOrders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Text('Orders from buyers will show up here.', style: Theme.of(context).textTheme.bodySmall),
                  )
                else
                  ...controller.recentOrders.map(
                    (order) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: ManifestStub(
                        code: order.code,
                        title: Formatters.currency(order.total, code: order.currency),
                        subtitle: Formatters.relative(order.createdAt),
                        accentColor: AppColors.statusColor(order.status.name),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
