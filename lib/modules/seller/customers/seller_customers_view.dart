import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_page.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/manifest_stub.dart';
import '../../../data/models/order_model.dart';
import 'customer_analytics.dart';
import 'seller_customers_controller.dart';

/// Who buys from the store: headline numbers, then a searchable list with
/// each customer's order history.
class SellerCustomersView extends GetView<SellerCustomersController> {
  const SellerCustomersView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Customers',
      subtitle: 'Everyone registered with your store or buying from it.',
      child: Obx(() {
        if (controller.isLoading.value) {
          return const AppLoadingState(label: 'Loading your customers…');
        }
        final error = controller.errorMessage.value;
        if (error != null) {
          return AppErrorState(message: error, onRetry: controller.load);
        }
        if (!controller.hasCustomers) {
          return const EmptyState(
            icon: Icons.people_outline,
            title: 'No customers yet',
            message: 'Customers appear here once they register with your '
                'store or place an order. Share your store link from '
                'Marketing to bring them in.',
          );
        }
        final code = controller.currencyCode;
        final visible = controller.visible;
        return RefreshIndicator(
          onRefresh: controller.load,
          child: ListView(
            children: [
              _SummaryGrid(summary: controller.summary.value!, code: code),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 320,
                    child: AppSearchField(
                      hintText: 'Search by name or email',
                      onChanged: controller.search,
                    ),
                  ),
                  DropdownButton<CustomerSort>(
                    value: controller.sortBy.value,
                    onChanged: (v) {
                      if (v != null) controller.sort(v);
                    },
                    items: [
                      for (final s in CustomerSort.values)
                        DropdownMenuItem(
                            value: s, child: Text('Sort: ${s.label}')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Text('No customer matches that search.',
                      style: Theme.of(context).textTheme.bodySmall),
                )
              else
                for (final customer in visible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: ManifestStub(
                      code: customer.email.isEmpty
                          ? 'NO EMAIL ON FILE'
                          : customer.email,
                      title: customer.name,
                      subtitle: _subtitle(customer),
                      accentColor: customer.isReturning
                          ? AppColors.horizonTeal
                          : customer.purchaseCount > 0
                              ? AppColors.cargoNavy
                              : AppColors.slateLight,
                      trailing: Text(
                          Formatters.currency(customer.totalSpent, code: code),
                          style: Theme.of(context).textTheme.titleSmall),
                      onTap: () => _openProfile(context, customer, code),
                    ),
                  ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        );
      }),
    );
  }

  static String _subtitle(CustomerStat c) {
    if (c.purchaseCount == 0) {
      return c.orders.isEmpty
          ? 'Registered${c.joinedAt == null ? '' : ' ${Formatters.date(c.joinedAt!)}'} · no orders yet'
          : '${c.orders.length} unpaid order${c.orders.length == 1 ? '' : 's'}';
    }
    final orders = '${c.purchaseCount} order${c.purchaseCount == 1 ? '' : 's'}';
    final last = c.lastOrderAt == null
        ? ''
        : ' · last ${Formatters.relative(c.lastOrderAt!)}';
    return '$orders$last${c.isReturning ? ' · returning' : ''}';
  }

  void _openProfile(BuildContext context, CustomerStat customer, String code) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _CustomerProfile(customer: customer, code: code),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary, required this.code});

  final CustomerSummary summary;
  final String code;

  @override
  Widget build(BuildContext context) {
    return GridView.extent(
      maxCrossAxisExtent: 260,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.sm,
      mainAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.5,
      children: [
        ManifestStatCard(
          label: 'Customers',
          value: '${summary.totalCustomers}',
          accentColor: AppColors.cargoNavy,
          delta: '${summary.purchasingCustomers} have bought',
        ),
        ManifestStatCard(
          label: 'Returning customers',
          value: '${summary.returningCustomers}',
          accentColor: AppColors.horizonTeal,
          delta:
              '${(summary.repeatRate * 100).toStringAsFixed(0)}% of buyers came back',
        ),
        ManifestStatCard(
          label: 'New customers',
          value: '${summary.newCustomers}',
          accentColor: AppColors.info,
          delta: 'First purchase in the last 30 days',
        ),
        ManifestStatCard(
          label: 'Average spend',
          value: Formatters.currency(summary.averageSpend, code: code),
          accentColor: AppColors.manifestGold,
          delta: 'Per customer who bought',
        ),
      ],
    );
  }
}

class _CustomerProfile extends StatelessWidget {
  const _CustomerProfile({required this.customer, required this.code});

  final CustomerStat customer;
  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(customer.name, style: theme.textTheme.titleLarge),
          if (customer.email.isNotEmpty)
            SelectableText(customer.email, style: theme.textTheme.bodyMedium),
          if (customer.joinedAt != null)
            Text('Customer since ${Formatters.date(customer.joinedAt!)}',
                style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _Figure('Total spent',
                  Formatters.currency(customer.totalSpent, code: code)),
              _Figure('Orders', '${customer.purchaseCount}'),
              _Figure('Average order',
                  Formatters.currency(customer.averageOrderValue, code: code)),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Order history'),
          const SizedBox(height: AppSpacing.sm),
          if (customer.orders.isEmpty)
            Text('No orders yet.', style: theme.textTheme.bodySmall)
          else
            for (final order in customer.orders)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: ManifestStub(
                  code: order.code,
                  title: Formatters.currency(order.total, code: order.currency),
                  subtitle: [
                    Formatters.date(order.createdAt),
                    order.status.label,
                    order.paymentStatus.label,
                    if (order.discountCode != null) order.discountCode!,
                  ].join(' · '),
                  accentColor: order.status == OrderStatus.cancelled
                      ? AppColors.slateLight
                      : AppColors.cargoNavy,
                ),
              ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}
