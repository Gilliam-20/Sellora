import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/manifest_stub.dart';
import '../../../data/models/store_model.dart';
import '../../../data/models/user_model.dart';
import 'admin_stores_controller.dart';

class AdminStoresView extends GetView<AdminStoresController> {
  const AdminStoresView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stores')),
      body: Obx(() {
        if (controller.isLoading.value) return const SelloraLoader();
        if (controller.stores.isEmpty) {
          return const EmptyState(
              icon: Icons.storefront_outlined,
              title: 'No stores yet',
              message:
                  'A store is created the moment a seller finishes signup.');
        }
        final filtered = controller.filtered;
        return RefreshIndicator(
          onRefresh: controller.load,
          child: ResponsiveCenter(
            maxWidth: 720,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(context.pageHorizontalPadding,
                      AppSpacing.md, context.pageHorizontalPadding, 0),
                  child: TextField(
                    onChanged: controller.setQuery,
                    decoration: const InputDecoration(
                      hintText: 'Search stores by name, slug, or owner',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? EmptyState(
                          icon: Icons.search_off,
                          title: 'No matches',
                          message:
                              'No store matches "${controller.query.value}".')
                      : ListView.separated(
                          padding: EdgeInsets.symmetric(
                              horizontal: context.pageHorizontalPadding,
                              vertical: AppSpacing.md),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, index) {
                            final store = filtered[index];
                            final seller = controller.sellerFor(store);
                            return ManifestStub(
                              code: '/s/${store.slug}',
                              title: store.name,
                              subtitle: seller == null
                                  ? 'Owner unknown · ${store.currencyCode}'
                                  : '${seller.name} · ${_statusLabel(seller.sellerStatus)} · ${store.currencyCode}',
                              accentColor: _statusColor(seller?.sellerStatus),
                              onTap: () => _showDetail(context, store, seller),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  void _showDetail(BuildContext context, StoreModel store, UserModel? seller) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(store.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text('/s/${store.slug}',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.md),
            _detailRow('Owner', seller?.name ?? 'Unknown'),
            _detailRow('Owner email', seller?.email ?? '—'),
            _detailRow('Seller status', _statusLabel(seller?.sellerStatus)),
            _detailRow('Currency', store.currencyCode),
            _detailRow(
                'Created',
                store.createdAt != null
                    ? Formatters.date(store.createdAt!)
                    : 'Unknown'),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
                width: 120,
                child: Text(label,
                    style: const TextStyle(color: AppColors.slate))),
            Expanded(child: Text(value)),
          ],
        ),
      );

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
