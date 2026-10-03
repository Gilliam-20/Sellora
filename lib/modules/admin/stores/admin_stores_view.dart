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
                              subtitle: [
                                if (store.isSuspended) 'Store suspended',
                                if (seller == null)
                                  'Owner unknown'
                                else ...[
                                  seller.name,
                                  _statusLabel(seller.sellerStatus),
                                ],
                                store.currencyCode,
                              ].join(' · '),
                              accentColor: store.isSuspended
                                  ? AppColors.danger
                                  : _statusColor(seller?.sellerStatus),
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
      isScrollControlled: true,
      builder: (context) => _StoreDetailSheet(
          store: store, seller: seller, buildBody: _detailBody),
    );
  }

  Widget _detailBody(BuildContext context, StoreModel store, UserModel? seller) =>
      Padding(
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
            _detailRow(
                'Store status',
                store.isSuspended
                    ? 'Suspended${store.suspendedAt != null ? ' since ${Formatters.date(store.suspendedAt!)}' : ''}'
                    : 'Live'),
            if (store.isSuspended && store.suspensionReason != null)
              _detailRow('Reason', store.suspensionReason!),
          ],
        ),
      );

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

/// The store's details plus the suspend/lift control. Stateful only for
/// the reason field and the in-sheet error.
class _StoreDetailSheet extends StatefulWidget {
  const _StoreDetailSheet(
      {required this.store, required this.seller, required this.buildBody});

  final StoreModel store;
  final UserModel? seller;
  final Widget Function(BuildContext, StoreModel, UserModel?) buildBody;

  @override
  State<_StoreDetailSheet> createState() => _StoreDetailSheetState();
}

class _StoreDetailSheetState extends State<_StoreDetailSheet> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit(bool suspend) async {
    final controller = Get.find<AdminStoresController>();
    final error = await controller.setSuspended(widget.store,
        suspended: suspend, reason: _reason.text);
    if (!mounted) return;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop();
    Get.snackbar(
      suspend ? 'Store suspended' : 'Suspension lifted',
      suspend
          ? '${widget.store.name} is offline: its catalog is hidden and checkout is closed.'
          : '${widget.store.name} is live again.',
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final controller = Get.find<AdminStoresController>();
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            widget.buildBody(context, store, widget.seller),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
              child: Obx(() {
                final busy = controller.updatingStoreId.value == store.id;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!store.isSuspended) ...[
                      Text(
                        'Suspending hides this store\'s catalog and closes its '
                        'checkout. The seller keeps their account and other '
                        'stores; suspend the seller instead to stop everything.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.slate),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _reason,
                        maxLength: 500,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Reason (the seller sees this)',
                        ),
                      ),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Text(_error!,
                            style: const TextStyle(color: AppColors.danger)),
                      ),
                    store.isSuspended
                        ? FilledButton.icon(
                            onPressed: busy ? null : () => _submit(false),
                            icon: const Icon(Icons.play_circle_outline),
                            label: const Text('Lift suspension'),
                          )
                        : OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.danger),
                            onPressed: busy ? null : () => _submit(true),
                            icon: const Icon(Icons.block),
                            label: const Text('Suspend store'),
                          ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
