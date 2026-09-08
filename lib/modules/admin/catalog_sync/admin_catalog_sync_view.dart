import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/responsive.dart';
import 'admin_catalog_sync_controller.dart';

class AdminCatalogSyncView extends GetView<AdminCatalogSyncController> {
  const AdminCatalogSyncView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CJ catalog sync')),
      body: ResponsiveCenter(
        maxWidth: 720,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.cloud,
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.sync, color: AppColors.adminAccent),
                      const SizedBox(width: AppSpacing.sm),
                      Text('Shared catalog', style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Pulls the latest products, prices and stock from CJ Dropshipping into the catalog sellers browse from. Run this daily or whenever CJ pricing changes.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Obx(() {
                    final last = controller.lastSyncedAt.value;
                    return Text(
                      last == null ? 'Never synced' : 'Last synced ${Formatters.dateTime(last)}',
                      style: Theme.of(context).textTheme.labelMedium,
                    );
                  }),
                  const SizedBox(height: AppSpacing.md),
                  Obx(
                    () => ElevatedButton.icon(
                      onPressed: controller.isSyncing.value ? null : controller.sync,
                      icon: controller.isSyncing.value
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink))
                          : const Icon(Icons.refresh, size: 18),
                      label: Text(controller.isSyncing.value ? 'Syncing…' : 'Sync now'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
