import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../data/models/order_model.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/app_page.dart';
import '../../../core/widgets/manifest_stub.dart';
import '../../storefront/store_scope.dart';
import '../shell/seller_shell_controller.dart';
import 'dashboard_models.dart';
import 'seller_dashboard_controller.dart';

class SellerDashboardView extends GetView<SellerDashboardController> {
  const SellerDashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final user = controller.authRepo.cachedUser;
    final currencyCode =
        Get.find<StoreScope>().current.value?.currencyCode ?? 'KES';

    return Scaffold(
      appBar: AppBar(title: Text(user?.storeName ?? 'Dashboard')),
      body: Obx(() {
        if (controller.isLoading.value) return const SelloraLoader();
        return RefreshIndicator(
          onRefresh: controller.load,
          child: ResponsiveCenter(
            maxWidth: 1100,
            child: ListView(
              padding: EdgeInsets.symmetric(
                  horizontal: context.pageHorizontalPadding,
                  vertical: AppSpacing.md),
              children: [
                AppPageHeader(
                  title: 'Welcome back',
                  subtitle: user?.hasActiveSubscription == true
                      ? 'Your subscription renews ${Formatters.date(user!.subscriptionActiveUntil!)}.'
                      : 'Your subscription needs attention.',
                ),
                const SizedBox(height: AppSpacing.lg),
                if (!controller.hasProduct.value ||
                    !controller.hasPublishedProduct.value ||
                    !controller.hasCustomizedStore.value ||
                    !controller.hasSale.value) ...[
                  const _OnboardingChecklist(),
                  const SizedBox(height: AppSpacing.lg),
                ],
                _DateRangeChips(controller: controller),
                const SizedBox(height: AppSpacing.md),
                _MetricsGrid(
                    controller: controller, currencyCode: currencyCode),
                const SizedBox(height: AppSpacing.lg),
                const SectionHeader(title: 'Sales'),
                const SizedBox(height: AppSpacing.sm),
                _SalesChartCard(
                    controller: controller, currencyCode: currencyCode),
                const SizedBox(height: AppSpacing.lg),
                if (context.isDesktop)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          child: _StatusBreakdownCard(controller: controller)),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: _TopProductsCard(
                            controller: controller, currencyCode: currencyCode),
                      ),
                    ],
                  )
                else ...[
                  _StatusBreakdownCard(controller: controller),
                  const SizedBox(height: AppSpacing.lg),
                  _TopProductsCard(
                      controller: controller, currencyCode: currencyCode),
                ],
                const SizedBox(height: AppSpacing.lg),
                _StoreHealthCard(controller: controller),
                const SizedBox(height: AppSpacing.lg),
                const SectionHeader(title: 'Recent orders'),
                const SizedBox(height: AppSpacing.sm),
                if (controller.recentOrders.isEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Text('Orders from buyers will show up here.',
                        style: Theme.of(context).textTheme.bodySmall),
                  )
                else
                  ...controller.recentOrders.map(
                    (order) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: ManifestStub(
                        code: order.code,
                        title: Formatters.currency(order.total,
                            code: order.currency),
                        subtitle: Formatters.relative(order.createdAt),
                        accentColor: AppColors.statusColor(order.status.name),
                      ),
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

class _DateRangeChips extends StatelessWidget {
  const _DateRangeChips({required this.controller});
  final SellerDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final option in DateRangeOption.values
                  .where((o) => o != DateRangeOption.custom))
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: ChoiceChip(
                    label: Text(option.label),
                    selected: controller.selectedRange.value == option,
                    onSelected: (_) => controller.selectRange(option),
                  ),
                ),
              ChoiceChip(
                label: Text(controller.selectedRange.value ==
                        DateRangeOption.custom
                    ? '${Formatters.date_(controller.customRange.value!.start)} – ${Formatters.date_(controller.customRange.value!.end)}'
                    : 'Custom'),
                selected:
                    controller.selectedRange.value == DateRangeOption.custom,
                onSelected: (_) async {
                  final now = DateTime.now();
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: now.subtract(const Duration(days: 730)),
                    lastDate: now,
                    initialDateRange: controller.customRange.value ??
                        DateTimeRange(
                            start: now.subtract(const Duration(days: 6)),
                            end: now),
                  );
                  if (picked != null) controller.selectCustomRange(picked);
                },
              ),
            ],
          ),
        ));
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.controller, required this.currencyCode});
  final SellerDashboardController controller;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return Obx(() => GridView.extent(
          maxCrossAxisExtent: 260,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: AppSpacing.sm,
          mainAxisSpacing: AppSpacing.sm,
          childAspectRatio: 1.5,
          children: [
            ManifestStatCard(
              label: 'Gross sales',
              value: Formatters.currency(controller.grossSales.value,
                  code: currencyCode),
              accentColor: AppColors.manifestGold,
              delta: _deltaLabel(controller.grossSalesDeltaPercent.value),
            ),
            ManifestStatCard(
              label: 'Your revenue',
              value: Formatters.currency(controller.netRevenue.value,
                  code: currencyCode),
              accentColor: AppColors.horizonTeal,
            ),
            ManifestStatCard(
              label: 'Orders',
              value: '${controller.orderCount.value}',
              accentColor: AppColors.info,
              delta: _deltaLabel(controller.ordersDeltaPercent.value),
            ),
            ManifestStatCard(
              label: 'Average order value',
              value: Formatters.currency(controller.averageOrderValue.value,
                  code: currencyCode),
              accentColor: AppColors.cargoNavy,
            ),
            ManifestStatCard(
              label: 'Active listings',
              value: '${controller.listingCount.value}',
              accentColor: AppColors.horizonTeal,
            ),
            GestureDetector(
              onTap: () => Get.find<SellerShellController>().changeTab(3),
              child: ManifestStatCard(
                label: 'Orders to fulfill',
                value: '${controller.pendingFulfillmentCount.value}',
                accentColor: AppColors.info,
              ),
            ),
          ],
        ));
  }

  String? _deltaLabel(double? percent) {
    if (percent == null) return null;
    final sign = percent >= 0 ? '+' : '';
    return '$sign${percent.toStringAsFixed(0)}% vs previous period';
  }
}

class _SalesChartCard extends StatelessWidget {
  const _SalesChartCard({required this.controller, required this.currencyCode});
  final SellerDashboardController controller;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final points = controller.salesSeries;
      final hasSales = points.any((p) => p.amount > 0);
      return Container(
        height: 260,
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.cloud,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: AppColors.hairline),
        ),
        child: !hasSales
            ? Center(
                child: Text('No paid sales in this period yet.',
                    style: Theme.of(context).textTheme.bodySmall),
              )
            : LineChart(_chartData(points)),
      );
    });
  }

  LineChartData _chartData(List<SalesPoint> points) {
    final maxY = points.map((p) => p.amount).fold(0.0, (a, b) => a > b ? a : b);
    final labelEvery = (points.length / 5).ceil().clamp(1, points.length);
    return LineChartData(
      minY: 0,
      maxY: maxY == 0 ? 1 : maxY * 1.2,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: maxY == 0 ? 1 : maxY / 3,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: AppColors.hairline, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: labelEvery.toDouble(),
            reservedSize: 26,
            getTitlesWidget: (value, meta) {
              final i = value.round();
              if (i < 0 || i >= points.length) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(Formatters.date_(points[i].bucketStart),
                    style:
                        const TextStyle(fontSize: 10, color: AppColors.slate)),
              );
            },
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) => spots
              .map((s) => LineTooltipItem(
                    Formatters.currency(s.y, code: currencyCode),
                    const TextStyle(
                        color: AppColors.cloud, fontWeight: FontWeight.w600),
                  ))
              .toList(),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: [
            for (var i = 0; i < points.length; i++)
              FlSpot(i.toDouble(), points[i].amount),
          ],
          isCurved: false,
          barWidth: 2,
          color: AppColors.manifestGoldDeep,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: AppColors.manifestGold.withValues(alpha: 0.12),
          ),
        ),
      ],
    );
  }
}

class _StatusBreakdownCard extends StatelessWidget {
  const _StatusBreakdownCard({required this.controller});
  final SellerDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final breakdown = controller.statusBreakdown;
      final total = breakdown.values.fold(0, (a, b) => a + b);
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.cloud,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Orders by status',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            if (total == 0)
              Text('No orders in this period.',
                  style: Theme.of(context).textTheme.bodySmall)
            else
              for (final status in OrderStatus.values)
                if ((breakdown[status] ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      children: [
                        StatusBadge(
                            label: status.label,
                            color: AppColors.statusColor(status.name)),
                        const Spacer(),
                        Text('${breakdown[status]}',
                            style: Theme.of(context).textTheme.titleSmall),
                      ],
                    ),
                  ),
          ],
        ),
      );
    });
  }
}

class _TopProductsCard extends StatelessWidget {
  const _TopProductsCard(
      {required this.controller, required this.currencyCode});
  final SellerDashboardController controller;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final products = controller.topProducts;
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.cloud,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Top products', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            if (products.isEmpty)
              Text('No paid sales in this period yet.',
                  style: Theme.of(context).textTheme.bodySmall)
            else
              for (final p in products)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(p.imageUrl,
                            width: 36,
                            height: 36,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                                width: 36, height: 36, color: AppColors.mist)),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(p.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text('${p.quantitySold} sold',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(width: AppSpacing.sm),
                      Text(Formatters.currency(p.revenue, code: currencyCode),
                          style: Theme.of(context).textTheme.titleSmall),
                    ],
                  ),
                ),
          ],
        ),
      );
    });
  }
}

class _StoreHealthCard extends StatelessWidget {
  const _StoreHealthCard({required this.controller});
  final SellerDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final usage = controller.usage.value;
      final plan = controller.plan.value;
      return GestureDetector(
        onTap: () => Get.toNamed(Routes.sellerSubscription),
        child: Container(
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Store health',
                      style: Theme.of(context).textTheme.titleSmall),
                  Text(plan?.name ?? 'No plan',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: AppColors.manifestGoldDeep)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (usage != null)
                _UsageBar(
                  label: 'Listings',
                  used: usage.listingCount,
                  limit: usage.listingLimit,
                ),
              if (plan != null && plan.orderLimit > 0) ...[
                const SizedBox(height: AppSpacing.xs),
                _UsageBar(
                  label: 'Orders this billing period',
                  used: controller.ordersThisPeriod.value,
                  limit: plan.orderLimit,
                ),
              ],
            ],
          ),
        ),
      );
    });
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar(
      {required this.label, required this.used, required this.limit});
  final String label;
  final int used;
  final int limit; // -1 means unlimited

  @override
  Widget build(BuildContext context) {
    final unlimited = limit < 0;
    final ratio = unlimited ? 0.0 : (used / limit).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Text(unlimited ? '$used used' : '$used / $limit',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        if (!unlimited) ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AppColors.mist,
              color: ratio >= 1
                  ? AppColors.danger
                  : ratio >= 0.8
                      ? AppColors.warning
                      : AppColors.horizonTeal,
            ),
          ),
        ],
      ],
    );
  }
}

class _OnboardingChecklist extends GetView<SellerDashboardController> {
  const _OnboardingChecklist();

  @override
  Widget build(BuildContext context) {
    final shell = Get.find<SellerShellController>();
    final items = <(String, bool, VoidCallback)>[
      (
        'Import your first product',
        controller.hasProduct.value,
        () => shell.changeTab(1)
      ),
      (
        'Publish a product to your storefront',
        controller.hasPublishedProduct.value,
        () => shell.changeTab(2)
      ),
      (
        'Customize your storefront',
        controller.hasCustomizedStore.value,
        () => Get.toNamed(Routes.sellerStoreCustomize)
      ),
      (
        'Make your first sale',
        controller.hasSale.value,
        () => shell.changeTab(3)
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cloud,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Get your store ready',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          for (final (label, done, onTap) in items)
            InkWell(
              onTap: done ? null : onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      done ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 18,
                      color: done ? AppColors.horizonTealDeep : AppColors.slate,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            decoration:
                                done ? TextDecoration.lineThrough : null,
                            color: done ? AppColors.slate : AppColors.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
