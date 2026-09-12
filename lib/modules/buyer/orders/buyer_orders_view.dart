import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sellora/data/models/order_model.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/manifest_stub.dart';
import 'buyer_orders_controller.dart';

class BuyerOrdersView extends GetView<BuyerOrdersController> {
  const BuyerOrdersView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your orders')),
      body: Obx(() {
        if (controller.isLoading.value) return const SelloraLoader();
        if (controller.orders.isEmpty) {
          return const EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No orders yet',
            message:
                'Products you buy will show up here with live tracking status.',
          );
        }
        return RefreshIndicator(
          onRefresh: controller.loadOrders,
          child: ResponsiveCenter(
            maxWidth: 720,
            child: ListView.separated(
              padding: EdgeInsets.symmetric(
                  horizontal: context.pageHorizontalPadding,
                  vertical: AppSpacing.md),
              itemCount: controller.orders.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final order = controller.orders[index];
                return ManifestStub(
                  code: order.code,
                  title:
                      '${order.items.length} item${order.items.length == 1 ? '' : 's'} · ${Formatters.currency(order.total, code: order.currency)}',
                  subtitle: Formatters.date(order.createdAt),
                  accentColor: AppColors.statusColor(order.status.name),
                  trailing: StatusBadge(
                    label: order.status.label,
                    color: AppColors.statusColor(order.status.name),
                  ),
                );
              },
            ),
          ),
        );
      }),
    );
  }
}
