import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_page.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../data/models/order_model.dart';
import '../../../data/services/currency_service.dart';
import '../../storefront/design/storefront_theme.dart';
import '../../storefront/shell/storefront_links.dart';
import '../../storefront/shell/storefront_page.dart';
import 'buyer_orders_controller.dart';

/// `/s/{slug}/account/orders`: the customer's order history with this
/// store. Each order opens its own page.
class BuyerOrdersView extends GetView<BuyerOrdersController> {
  const BuyerOrdersView({super.key});

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    return StorefrontPage(
      title: 'Your orders',
      onRefresh: controller.loadOrders,
      slivers: (context, store, design) {
        final style = StoreStyle.of(context);
        final textTheme = Theme.of(context).textTheme;
        return [
          SliverToBoxAdapter(
            child: StorefrontContent(
              maxWidth: 760,
              child: Obx(() {
                final isLoading = controller.isLoading.value;
                final orders = List.of(controller.orders);
                final heading = Text(style.heading('Your orders'),
                    style: style.headingStyle(textTheme.headlineSmall));
                Widget body;
                if (session.customer == null && !isLoading) {
                  body = EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'Sign in to see your orders',
                    message: 'Create an account or sign in to track your '
                        'purchases from this store.',
                    actionLabel: 'Sign in',
                    onAction: () => Get.toNamed(session.path(
                        StorefrontPaths.loginThen(
                            session.path(StorefrontPaths.orders)))),
                  );
                } else if (isLoading) {
                  body = const SizedBox(height: 200, child: AppLoadingState());
                } else if (controller.error.value case final error?) {
                  body = AppErrorState(
                      message: error, onRetry: controller.loadOrders);
                } else if (orders.isEmpty) {
                  body = EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No orders yet',
                    message: 'What you buy here will show up with its '
                        'delivery status.',
                    actionLabel: 'Start shopping',
                    onAction: () =>
                        Get.offAllNamed(session.path(StorefrontPaths.shop)),
                  );
                } else {
                  final currency = Get.find<CurrencyService>();
                  body = Column(
                    children: [
                      for (final order in orders)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius:
                                  BorderRadius.circular(style.largeRadius),
                              onTap: () => Get.toNamed(session
                                  .path(StorefrontPaths.order(order.id))),
                              child: Ink(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                decoration: style.panel(),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(order.code,
                                              style: textTheme.titleSmall),
                                          Text(
                                              '${Formatters.date(order.createdAt)} · '
                                              '${order.itemCount} item${order.itemCount == 1 ? '' : 's'} · '
                                              '${currency.format(order.total, fromCode: order.currency)}',
                                              style: textTheme.bodySmall),
                                        ],
                                      ),
                                    ),
                                    Text(order.status.label,
                                        style: textTheme.labelLarge),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heading,
                    const SizedBox(height: AppSpacing.md),
                    body,
                  ],
                );
              }),
            ),
          ),
        ];
      },
    );
  }
}
