import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/responsive.dart';
import '../../../data/models/user_model.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/manifest_stub.dart';
import 'admin_sellers_controller.dart';

class AdminSellersView extends GetView<AdminSellersController> {
  const AdminSellersView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sellers')),
      body: Obx(() {
        if (controller.isLoading.value) return const SelloraLoader();
        if (controller.sellers.isEmpty) {
          return const EmptyState(
              icon: Icons.storefront_outlined,
              title: 'No sellers yet',
              message: 'New signups will show up here for approval.');
        }
        return RefreshIndicator(
          onRefresh: controller.load,
          child: ResponsiveCenter(
            maxWidth: 720,
            child: ListView.separated(
              padding: EdgeInsets.symmetric(
                  horizontal: context.pageHorizontalPadding,
                  vertical: AppSpacing.md),
              itemCount: controller.sellers.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final seller = controller.sellers[index];
                return ManifestStub(
                  code: seller.email,
                  title: seller.storeName ?? seller.name,
                  subtitle: _statusLabel(seller.sellerStatus),
                  accentColor: _statusColor(seller.sellerStatus),
                  trailing: seller.sellerStatus == SellerStatus.pendingApproval
                      ? ElevatedButton(
                          onPressed: () => controller.approve(seller.uid),
                          child: const Text('Approve'))
                      : seller.sellerStatus == SellerStatus.active
                          ? TextButton(
                              onPressed: () => controller.suspend(seller.uid),
                              style: TextButton.styleFrom(
                                  foregroundColor: AppColors.danger),
                              child: const Text('Suspend'),
                            )
                          : OutlinedButton(
                              onPressed: () => controller.approve(seller.uid),
                              child: const Text('Reinstate')),
                );
              },
            ),
          ),
        );
      }),
    );
  }

  String _statusLabel(SellerStatus? status) => switch (status) {
        SellerStatus.active => 'Active',
        SellerStatus.pendingApproval => 'Pending approval',
        SellerStatus.suspended => 'Suspended',
        null => 'Unknown',
      };

  Color _statusColor(SellerStatus? status) => switch (status) {
        SellerStatus.active => AppColors.horizonTeal,
        SellerStatus.pendingApproval => AppColors.manifestGold,
        SellerStatus.suspended => AppColors.danger,
        null => AppColors.slate,
      };
}
