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
import '../../../data/repositories/auth_repository.dart';
import '../../../data/services/currency_service.dart';
import 'buyer_orders_controller.dart';

class BuyerOrdersView extends GetView<BuyerOrdersController> {
  const BuyerOrdersView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your orders')),
      body: Obx(() {
        // Touch an observable unconditionally first — cachedUser below isn't
        // reactive, so if the guest branch returned without this read, Obx
        // would never find an observable to subscribe to and would throw.
        final isLoading = controller.isLoading.value;
        if (Get.find<AuthRepository>().cachedUser == null) {
          return EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'Sign in to see your orders',
            message: 'Create an account or sign in to track your purchases '
                'from this store.',
            actionLabel: 'Sign in',
            onAction: () => Get.toNamed('/s/${Get.parameters['slug']}/login'),
          );
        }
        if (isLoading) return const SelloraLoader();
        // Snapshot the RxList once here, inside Obx's tracked scope — the
        // ListView's itemBuilder runs later during layout, outside that
        // scope, so indexing controller.orders directly there would read
        // the observable where GetX can no longer see it.
        final orders = List.of(controller.orders);
        if (orders.isEmpty) {
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
              itemCount: orders.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final order = orders[index];
                return Obx(() {
                  final total = Get.find<CurrencyService>()
                      .format(order.total, fromCode: order.currency);
                  return ManifestStub(
                    code: order.code,
                    title:
                        '${order.items.length} item${order.items.length == 1 ? '' : 's'} · $total',
                    subtitle: Formatters.date(order.createdAt),
                    accentColor: AppColors.statusColor(order.status.name),
                    trailing: StatusBadge(
                      label: order.status.label,
                      color: AppColors.statusColor(order.status.name),
                    ),
                  );
                });
              },
            ),
          ),
        );
      }),
    );
  }
}
