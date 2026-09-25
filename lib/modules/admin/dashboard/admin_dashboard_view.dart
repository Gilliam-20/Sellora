import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/manifest_stub.dart';
import 'admin_dashboard_controller.dart';
import 'admin_dashboard_models.dart';

class AdminDashboardView extends GetView<AdminDashboardController> {
  const AdminDashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Platform overview')),
      body: Obx(() {
        if (controller.isLoading.value) return const SelloraLoader();
        return RefreshIndicator(
          onRefresh: controller.load,
          child: ResponsiveCenter(
            maxWidth: 900,
            child: ListView(
              padding: EdgeInsets.symmetric(
                  horizontal: context.pageHorizontalPadding,
                  vertical: AppSpacing.md),
              children: [
                const SectionHeader(title: 'Platform revenue'),
                const SizedBox(height: AppSpacing.sm),
                _statGrid([
                  ManifestStatCard(
                      label: 'Seller GMV',
                      value:
                          Formatters.currency(controller.totalGmv, code: 'KES'),
                      accentColor: AppColors.cargoNavy),
                  ManifestStatCard(
                      label: 'Service fee revenue',
                      value: Formatters.currency(controller.serviceFeeRevenue,
                          code: 'KES'),
                      accentColor: AppColors.manifestGold),
                  ManifestStatCard(
                      label: 'Subscription MRR',
                      value: Formatters.currency(controller.subscriptionMrr,
                          code: 'KES'),
                      accentColor: AppColors.horizonTeal),
                  ManifestStatCard(
                      label: 'Total platform revenue',
                      value: Formatters.currency(
                          controller.totalPlatformRevenue,
                          code: 'KES'),
                      accentColor: AppColors.adminAccent),
                ]),
                const SizedBox(height: AppSpacing.lg),
                const _PlatformTrendCard(),
                const SizedBox(height: AppSpacing.lg),
                const SectionHeader(title: 'Sellers & stores'),
                const SizedBox(height: AppSpacing.sm),
                _statGrid([
                  ManifestStatCard(
                      label: 'Active sellers',
                      value: '${controller.activeSellerCount}',
                      accentColor: AppColors.horizonTeal),
                  ManifestStatCard(
                      label: 'Pending approval',
                      value: '${controller.pendingSellerCount}',
                      accentColor: AppColors.manifestGold),
                  ManifestStatCard(
                      label: 'Suspended',
                      value: '${controller.suspendedSellerCount}',
                      accentColor: AppColors.danger),
                  ManifestStatCard(
                      label: 'New sellers (30d)',
                      value: '${controller.newSellerCount30d}',
                      accentColor: AppColors.info),
                  ManifestStatCard(
                      label: 'Stores',
                      value: '${controller.stores.length}',
                      accentColor: AppColors.cargoNavy),
                  ManifestStatCard(
                      label: 'Total orders',
                      value: '${controller.orders.length}',
                      accentColor: AppColors.adminAccent),
                ]),
                const SizedBox(height: AppSpacing.lg),
                Text('Recent orders across all sellers',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                if (controller.orders.isEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Text('No orders on the platform yet.',
                        style: Theme.of(context).textTheme.bodySmall),
                  )
                else
                  ...controller.orders.take(6).map(
                        (order) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: ManifestStub(
                            code: order.code,
                            title: Formatters.currency(order.total,
                                code: order.currency),
                            subtitle:
                                'Seller: ${order.sellerId} · ${Formatters.relative(order.createdAt)}',
                            accentColor:
                                AppColors.statusColor(order.status.name),
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

  Widget _statGrid(List<Widget> cards) => GridView.extent(
        // A fixed 2-column count stayed 2-up all the way to a desktop
        // window; an extent-based grid grows toward 4 stat tiles per row
        // as the viewport widens instead.
        maxCrossAxisExtent: 260,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
        childAspectRatio: 1.5,
        children: cards,
      );
}

class _PlatformTrendCard extends GetView<AdminDashboardController> {
  const _PlatformTrendCard();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final metric = controller.selectedTrendMetric.value;
      final points = controller.platformTrend;
      final hasValues = points.any((point) => point.amountFor(metric) > 0);
      final accent = metric == AdminTrendMetric.gmv
          ? AppColors.cargoNavy
          : AppColors.manifestGoldDeep;

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
            Text('Platform performance',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              metric == AdminTrendMetric.gmv
                  ? 'Paid order value across seller stores.'
                  : 'Sellora service fees from paid orders only.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.slate),
            ),
            const SizedBox(height: AppSpacing.sm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final days in [7, 30, 90])
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: ChoiceChip(
                        label: Text('Last $days days'),
                        selected: controller.selectedTrendDays.value == days,
                        onSelected: (_) => controller.selectTrendDays(days),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            SegmentedButton<AdminTrendMetric>(
              segments: [
                for (final option in AdminTrendMetric.values)
                  ButtonSegment(value: option, label: Text(option.label)),
              ],
              selected: {metric},
              onSelectionChanged: (selection) =>
                  controller.selectTrendMetric(selection.first),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 190,
              child: hasValues
                  ? LineChart(_chartData(points, metric, accent))
                  : Center(
                      child: Text(
                        metric == AdminTrendMetric.gmv
                            ? 'No paid orders in this period yet.'
                            : 'No service-fee revenue is recorded in this period.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
            ),
          ],
        ),
      );
    });
  }

  LineChartData _chartData(
    List<PlatformTrendPoint> points,
    AdminTrendMetric metric,
    Color accent,
  ) {
    final amounts = points.map((point) => point.amountFor(metric)).toList();
    final maxY = amounts.fold(0.0, (max, amount) => amount > max ? amount : max);
    final labelEvery = (points.length / 5).ceil().clamp(1, points.length);
    return LineChartData(
      minY: 0,
      maxY: maxY * 1.2,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: maxY / 3,
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
              final index = value.round();
              if (index < 0 || index >= points.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  Formatters.date_(points[index].day),
                  style: const TextStyle(fontSize: 10, color: AppColors.slate),
                ),
              );
            },
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) => spots.map((spot) {
            final point = points[spot.x.round()];
            return LineTooltipItem(
              '${Formatters.date_(point.day)}\n${Formatters.currency(spot.y, code: 'KES')}',
              const TextStyle(
                color: AppColors.cloud,
                fontWeight: FontWeight.w600,
              ),
            );
          }).toList(),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: [
            for (var index = 0; index < amounts.length; index++)
              FlSpot(index.toDouble(), amounts[index]),
          ],
          isCurved: false,
          barWidth: 2,
          color: accent,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: accent.withValues(alpha: 0.12),
          ),
        ),
      ],
    );
  }
}
