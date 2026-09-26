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
import 'seller_orders_controller.dart';

class SellerOrdersView extends GetView<SellerOrdersController> {
  const SellerOrdersView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Orders to fulfill')),
      body: Obx(() {
        if (controller.isLoading.value) return const SelloraLoader();
        if (controller.orders.isEmpty) {
          return const EmptyState(
            icon: Icons.local_shipping_outlined,
            title: 'No orders yet',
            message:
                'Orders buyers place from your listings will show up here.',
          );
        }
        return RefreshIndicator(
          onRefresh: controller.load,
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
                  title: Formatters.currency(order.total, code: order.currency),
                  subtitle:
                      '${order.items.length} item${order.items.length == 1 ? '' : 's'} · ${order.status.label}',
                  accentColor: AppColors.statusColor(order.status.name),
                  trailing: _trailing(context, controller, order),
                );
              },
            ),
          ),
        );
      }),
    );
  }

  Widget? _trailing(BuildContext context, SellerOrdersController controller,
      OrderModel order) {
    final next = SellerOrdersController.nextStatus(order);
    if (next != null) {
      return TextButton(
        onPressed: () => controller.advanceStatus(order),
        child: Text(
            next == OrderStatus.shipped ? 'Mark shipped' : 'Mark delivered'),
      );
    }
    if (order.status == OrderStatus.pending) {
      return Text('Awaiting payment',
          style: Theme.of(context).textTheme.bodySmall);
    }
    return null;
  }
}
