import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/responsive.dart';
import '../../../data/models/order_model.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_page.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/manifest_stub.dart';
import 'order_filters.dart';
import 'seller_orders_controller.dart';

/// The seller's order list (TODO.md §14): every order with its customer,
/// date, total, payment and fulfilment state, items, shipping and channel,
/// filterable and searchable. Tapping one opens [SellerOrderDetailView].
class SellerOrdersView extends GetView<SellerOrdersController> {
  const SellerOrdersView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      body: Obx(() {
        if (controller.isLoading.value && controller.orders.isEmpty) {
          return const SelloraLoader();
        }
        if (controller.errorMessage.value != null &&
            controller.orders.isEmpty) {
          return AppErrorState(
              message: controller.errorMessage.value!,
              onRetry: controller.load);
        }
        if (controller.orders.isEmpty) {
          return const EmptyState(
            icon: Icons.local_shipping_outlined,
            title: 'No orders yet',
            message:
                'Orders buyers place from your listings will show up here.',
          );
        }
        final visible = controller.visibleOrders;
        return RefreshIndicator(
          onRefresh: controller.load,
          child: ResponsiveCenter(
            maxWidth: 820,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(context.pageHorizontalPadding,
                      AppSpacing.md, context.pageHorizontalPadding, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppSearchField(
                          hintText: 'Search order, customer, email or phone',
                          onChanged: (value) => controller.query.value = value,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _FilterChips(controller: controller),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ),
                  ),
                ),
                if (visible.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.filter_alt_off_outlined,
                      title: 'No matching orders',
                      message: 'Try another filter or search.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(context.pageHorizontalPadding,
                        0, context.pageHorizontalPadding, AppSpacing.lg),
                    sliver: SliverList.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) =>
                          _OrderRow(order: visible[index]),
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

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.controller});
  final SellerOrdersController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: OrderFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, index) {
          final f = OrderFilter.values[index];
          return Obx(() => ChoiceChip(
                label: Text('${f.label} (${controller.countFor(f)})'),
                selected: controller.filter.value == f,
                selectedColor: AppColors.manifestGold.withValues(alpha: 0.3),
                onSelected: (_) => controller.filter.value = f,
              ));
        },
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});
  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SellerOrdersController>();
    final shipping = [
      if (order.shippingAddress.countryCode.isNotEmpty)
        order.shippingAddress.countryCode,
      if (order.logisticName != null) order.logisticName!,
    ].join(' · ');
    return ManifestStub(
      code: '${order.code} · ${Formatters.date(order.createdAt)}',
      title:
          '${order.customerName} · ${Formatters.currency(order.total, code: order.currency)}',
      subtitle: [
        '${order.itemCount} item${order.itemCount == 1 ? '' : 's'}',
        if (shipping.isNotEmpty) shipping,
        order.channelLabel,
      ].join(' · '),
      accentColor: AppColors.statusColor(order.status.name),
      onTap: () => controller.openDetail(order),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          StatusBadge(
              label: order.paymentStatus.label,
              color: paymentColor(order.paymentStatus)),
          const SizedBox(height: 4),
          StatusBadge(
              label: order.fulfillmentLabel,
              color: AppColors.statusColor(order.status.name)),
        ],
      ),
    );
  }
}

/// The payment badge's color, shared with the detail screen.
Color paymentColor(OrderPaymentStatus status) => switch (status) {
      OrderPaymentStatus.paid => AppColors.horizonTealDeep,
      OrderPaymentStatus.pending => AppColors.manifestGoldDeep,
      OrderPaymentStatus.failed => AppColors.danger,
      OrderPaymentStatus.partiallyRefunded ||
      OrderPaymentStatus.refunded =>
        AppColors.slate,
    };
