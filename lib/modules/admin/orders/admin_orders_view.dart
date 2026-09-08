import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/responsive.dart';
import '../../../data/models/order_model.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/manifest_stub.dart';
import 'admin_orders_controller.dart';

class AdminOrdersView extends GetView<AdminOrdersController> {
  const AdminOrdersView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('All orders')),
      body: ResponsiveCenter(
        maxWidth: 900,
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: Obx(
                () => ListView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: context.pageHorizontalPadding, vertical: AppSpacing.sm),
                  children: [
                    _FilterChip(label: 'All', selected: controller.statusFilter.value == null, onTap: () => controller.setFilter(null)),
                    const SizedBox(width: AppSpacing.sm),
                    ...OrderStatus.values.map(
                      (status) => Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: _FilterChip(
                          label: status.label,
                          selected: controller.statusFilter.value == status,
                          onTap: () => controller.setFilter(status),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Obx(() {
                if (controller.isLoading.value) return const SelloraLoader();
                final orders = controller.filtered;
                if (orders.isEmpty) {
                  return const EmptyState(icon: Icons.receipt_long_outlined, title: 'No orders', message: 'Nothing matches this filter yet.');
                }
                return RefreshIndicator(
                  onRefresh: controller.load,
                  child: ListView.separated(
                    padding: EdgeInsets.symmetric(horizontal: context.pageHorizontalPadding, vertical: AppSpacing.md),
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      return ManifestStub(
                        code: order.code,
                        title: Formatters.currency(order.total, code: order.currency),
                        subtitle: 'Seller: ${order.sellerId} · Buyer: ${order.buyerId}',
                        accentColor: AppColors.statusColor(order.status.name),
                        trailing: Text(order.status.label, style: Theme.of(context).textTheme.labelMedium),
                      );
                    },
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppColors.cargoNavy,
      labelStyle: TextStyle(color: selected ? AppColors.cloud : AppColors.ink, fontWeight: FontWeight.w600),
      onSelected: (_) => onTap(),
    );
  }
}
