import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/manifest_stub.dart';
import 'admin_dashboard_controller.dart';

class AdminDashboardView extends GetView<AdminDashboardController> {
  const AdminDashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Platform overview')),
      body: Obx(() {
        if (controller.isLoading.value) return const SelloraLoader();
        return RefreshIndicator(
          onRefresh: controller.load,
          child: ResponsiveCenter(
            maxWidth: 900,
            child: ListView(
              padding: EdgeInsets.symmetric(
                  horizontal: context.pageHorizontalPadding,
                  vertical: AppSpacing.md),
              children: [
                const SectionHeader(title: 'Platform revenue'),
                const SizedBox(height: AppSpacing.sm),
                _statGrid([
                  ManifestStatCard(
                      label: 'Seller GMV',
                      value:
                          Formatters.currency(controller.totalGmv, code: 'KES'),
                      accentColor: AppColors.cargoNavy),
                  ManifestStatCard(
                      label: 'Service fee revenue',
                      value: Formatters.currency(controller.serviceFeeRevenue,
                          code: 'KES'),
                      accentColor: AppColors.manifestGold),
                  ManifestStatCard(
                      label: 'Subscription MRR',
                      value: Formatters.currency(controller.subscriptionMrr,
                          code: 'KES'),
                      accentColor: AppColors.horizonTeal),
                  ManifestStatCard(
                      label: 'Total platform revenue',
                      value: Formatters.currency(
                          controller.totalPlatformRevenue,
                          code: 'KES'),
                      accentColor: AppColors.adminAccent),
                ]),
                const SizedBox(height: AppSpacing.lg),
                const SectionHeader(title: 'Sellers & stores'),
                const SizedBox(height: AppSpacing.sm),
                _statGrid([
                  ManifestStatCard(
                      label: 'Active sellers',
                      value: '${controller.activeSellerCount}',
                      accentColor: AppColors.horizonTeal),
                  ManifestStatCard(
                      label: 'Pending approval',
                      value: '${controller.pendingSellerCount}',
                      accentColor: AppColors.manifestGold),
                  ManifestStatCard(
                      label: 'Suspended',
                      value: '${controller.suspendedSellerCount}',
                      accentColor: AppColors.danger),
                  ManifestStatCard(
                      label: 'New sellers (30d)',
                      value: '${controller.newSellerCount30d}',
                      accentColor: AppColors.info),
                  ManifestStatCard(
                      label: 'Stores',
                      value: '${controller.stores.length}',
                      accentColor: AppColors.cargoNavy),
                  ManifestStatCard(
                      label: 'Total orders',
                      value: '${controller.orders.length}',
                      accentColor: AppColors.adminAccent),
                ]),
                const SizedBox(height: AppSpacing.lg),
                Text('Recent orders across all sellers',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                if (controller.orders.isEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Text('No orders on the platform yet.',
                        style: Theme.of(context).textTheme.bodySmall),
                  )
                else
                  ...controller.orders.take(6).map(
                        (order) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: ManifestStub(
                            code: order.code,
                            title: Formatters.currency(order.total,
                                code: order.currency),
                            subtitle:
                                'Seller: ${order.sellerId} · ${Formatters.relative(order.createdAt)}',
                            accentColor:
                                AppColors.statusColor(order.status.name),
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

  Widget _statGrid(List<Widget> cards) => GridView.extent(
        // A fixed 2-column count stayed 2-up all the way to a desktop
        // window; an extent-based grid grows toward 4 stat tiles per row
        // as the viewport widens instead.
        maxCrossAxisExtent: 260,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
        childAspectRatio: 1.5,
        children: cards,
      );
}
