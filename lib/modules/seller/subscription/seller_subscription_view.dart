import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/plan_change.dart';
import '../../../core/utils/plan_text.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/app_page.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/manifest_stub.dart';
import '../../../data/models/billing_history_entry_model.dart';
import '../../../data/models/billing_profile_model.dart';
import '../../../data/models/subscription_plan_model.dart';
import '../../../data/models/subscription_usage_model.dart';
import 'billing_sheets.dart';
import 'seller_subscription_controller.dart';

/// Subscription & billing (TODO §17): the current plan and its status,
/// usage against each limit, the payment method, plans to move to, and
/// billing history with invoices.
class SellerSubscriptionView extends GetView<SellerSubscriptionController> {
  const SellerSubscriptionView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Subscription & billing')),
      body: Obx(() {
        if (controller.isLoading.value && controller.plans.isEmpty) {
          return const AppLoadingState();
        }
        if (controller.loadError.value case final error?
            when controller.plans.isEmpty) {
          return AppErrorState(message: error, onRetry: controller.load);
        }
        final usage = controller.usage.value;
        final upgrade = controller.suggestedUpgrade;
        return RefreshIndicator(
          onRefresh: controller.refreshStatus,
          child: ResponsiveCenter(
            maxWidth: 720,
            child: ListView(
              padding: EdgeInsets.symmetric(
                  horizontal: context.pageHorizontalPadding,
                  vertical: AppSpacing.lg),
              children: [
                const _PlanHeader(),
                for (final entry in controller.pendingPayments) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _PendingPayment(entry: entry),
                ],
                if (upgrade != null && usage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _UpgradeNudge(plan: upgrade, usage: usage),
                ],
                if (usage != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  const SectionHeader(title: 'Usage'),
                  const SizedBox(height: AppSpacing.xs),
                  _UsageCard(usage: usage),
                ],
                const SizedBox(height: AppSpacing.lg),
                SectionHeader(
                  title: 'Payment method',
                  action: 'Edit',
                  onAction: () => showBillingSheet(const PaymentMethodSheet()),
                ),
                _PaymentMethodCard(profile: controller.billingProfile.value),
                const SizedBox(height: AppSpacing.lg),
                const SectionHeader(title: 'Plans'),
                const SizedBox(height: AppSpacing.xs),
                ...controller.offeredPlans.map((plan) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _PlanCard(plan: plan),
                    )),
                const SizedBox(height: AppSpacing.md),
                const SectionHeader(title: 'Billing history'),
                const SizedBox(height: AppSpacing.xs),
                if (controller.history.isEmpty)
                  Text('No payments yet.',
                      style: Theme.of(context).textTheme.bodySmall)
                else
                  ...controller.history.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: _BillingRow(entry: e),
                      )),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _PlanHeader extends GetView<SellerSubscriptionController> {
  const _PlanHeader();

  @override
  Widget build(BuildContext context) => Obx(() => _build(context));

  Widget _build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final plan = controller.currentPlan;
    final usage = controller.usage.value;
    final end = usage?.currentPeriodEnd ??
        controller.authRepo.cachedUser?.subscriptionActiveUntil;
    final status = usage?.subscriptionStatus ?? 'none';
    final (statusLabel, statusColor) = switch (status) {
      _ when usage?.isEnding == true => ('Ending', AppColors.manifestGold),
      'active' => ('Active', AppColors.horizonTeal),
      'lapsed' => ('Lapsed', AppColors.danger),
      'cancelled' => ('Cancelled', AppColors.slateLight),
      _ => ('No plan', AppColors.slateLight),
    };
    // Nothing renews by itself: each period is a payment the seller makes,
    // so the date is when to pay by, not when they'll be charged.
    final dateLine = switch (status) {
      _ when end == null => null,
      _ when usage?.isEnding == true =>
        'Ends ${Formatters.date(end)}. You won\'t be reminded to renew.',
      'active' =>
        'Paid through ${Formatters.date(end)}. Renew by then to keep selling. '
            'We\'ll remind you 3 days before.',
      'lapsed' => 'Ended ${Formatters.date(end)}. Renew to keep selling.',
      _ => null,
    };
    final isRunning = usage?.isActive ?? false;
    final busy = controller.isChangingStatus.value;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cargoNavy,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Current plan',
                    style: textTheme.labelMedium
                        ?.copyWith(color: AppColors.slateLight)),
              ),
              StatusBadge(label: statusLabel, color: statusColor),
            ],
          ),
          const SizedBox(height: 4),
          Text(plan?.name ?? 'None',
              style: textTheme.displaySmall
                  ?.copyWith(color: AppColors.cloud, fontSize: 24)),
          if (plan != null)
            Text(
                '${Formatters.currency(plan.priceKes, code: 'KES')} / ${PlanText.period(plan.billingPeriodDays)}',
                style: textTheme.bodyMedium?.copyWith(color: AppColors.cloud)),
          if (dateLine != null) ...[
            const SizedBox(height: 4),
            Text(dateLine,
                style:
                    textTheme.bodySmall?.copyWith(color: AppColors.slateLight)),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (plan != null)
                ElevatedButton(
                  onPressed: () => showBillingSheet(PayPlanSheet(plan: plan)),
                  child: const Text('Renew now'),
                ),
              if (isRunning && usage!.isEnding)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.cloud,
                      side: const BorderSide(color: AppColors.slateLight)),
                  onPressed: busy ? null : controller.resume,
                  child: const Text('Resume plan'),
                )
              else if (isRunning)
                TextButton(
                  onPressed: busy
                      ? null
                      : () => showBillingSheet(const CancelPlanSheet()),
                  child: const Text('Cancel plan',
                      style: TextStyle(color: AppColors.slateLight)),
                ),
              TextButton(
                onPressed: controller.isRefreshing.value
                    ? null
                    : controller.refreshStatus,
                child: Text(
                  controller.isRefreshing.value
                      ? 'Refreshing…'
                      : 'Refresh status',
                  style: const TextStyle(color: AppColors.cloud),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PendingPayment extends GetView<SellerSubscriptionController> {
  const _PendingPayment({required this.entry});
  final BillingHistoryEntryModel entry;

  @override
  Widget build(BuildContext context) => Obx(() => _build(context));

  Widget _build(BuildContext context) {
    final checking = controller.checkingEntryId.value == entry.id;
    return ManifestStub(
      code: 'PAYMENT IN PROGRESS',
      title:
          '${entry.planName} · ${Formatters.currency(entry.amountKes, code: 'KES')}',
      subtitle:
          'Started ${Formatters.relative(entry.createdAt)}${entry.paymentMethodLabel == null ? '' : ' by ${entry.paymentMethodLabel}'}',
      accentColor: AppColors.manifestGold,
      trailing: TextButton(
        onPressed: checking ? null : () => controller.checkPayment(entry),
        child: Text(checking ? 'Checking…' : 'Check payment'),
      ),
    );
  }
}

class _UpgradeNudge extends StatelessWidget {
  const _UpgradeNudge({required this.plan, required this.usage});
  final SubscriptionPlanModel plan;
  final SubscriptionUsageModel usage;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tight = [
      if (_near(usage.listingCount, usage.listingLimit))
        '${usage.listingCount} of ${usage.listingLimit} listed products',
      if (_near(usage.orderCount, usage.orderLimit))
        '${usage.orderCount} of ${usage.orderLimit} paid orders',
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.manifestGold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.stub),
        border: const Border(
            left: BorderSide(color: AppColors.manifestGold, width: 4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('You\'re close to your limit',
                    style: textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  'You\'ve used ${tight.join(' and ')}. ${plan.name} gives you '
                  '${PlanText.highlights(plan).take(3).join(', ').toLowerCase()}.',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ElevatedButton(
            onPressed: () => showBillingSheet(PayPlanSheet(plan: plan)),
            child: Text('See ${plan.name}'),
          ),
        ],
      ),
    );
  }
}

bool _near(int used, int limit) => limit > 0 && used >= limit * 0.8;

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.usage});
  final SubscriptionUsageModel usage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cloud,
        borderRadius: BorderRadius.circular(AppRadii.stub),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          _UsageMeter(
              label: 'Listed products',
              used: usage.listingCount,
              limit: usage.listingLimit),
          const SizedBox(height: AppSpacing.md),
          _UsageMeter(
              label: 'Paid orders, last ${usage.billingPeriodDays} days',
              used: usage.orderCount,
              limit: usage.orderLimit),
          const SizedBox(height: AppSpacing.md),
          _UsageMeter(
              label: 'Stores', used: usage.storeCount, limit: usage.storeLimit),
        ],
      ),
    );
  }
}

class _UsageMeter extends StatelessWidget {
  const _UsageMeter(
      {required this.label, required this.used, required this.limit});
  final String label;
  final int used;

  /// -1 is unlimited.
  final int limit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final unlimited = limit < 0;
    final share =
        unlimited || limit == 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);
    final color = share >= 1
        ? AppColors.danger
        : share >= 0.8
            ? AppColors.manifestGoldDeep
            : AppColors.horizonTeal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: textTheme.bodyMedium)),
            Text(unlimited ? '$used · unlimited' : '$used of $limit',
                style: textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.control),
          child: LinearProgressIndicator(
            value: unlimited ? 0 : share,
            minHeight: 6,
            color: color,
            backgroundColor: AppColors.mist,
          ),
        ),
      ],
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard({required this.profile});
  final BillingProfileModel? profile;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final p = profile;
    final (icon, title, detail) = switch (p?.paymentMethod) {
      null => (
          Icons.account_balance_wallet_outlined,
          'None saved',
          'You choose M-Pesa or card each time you pay.'
        ),
      BillingPaymentMethod.mpesa => (
          Icons.phone_android,
          'M-Pesa',
          p!.mpesaPhoneDisplay ?? ''
        ),
      BillingPaymentMethod.card => (
          Icons.credit_card,
          'Card',
          'Paid on IntaSend\'s secure page. No card is stored.'
        ),
    };
    final invoiceTo = [
      if (p?.billingName case final name?) 'Invoices to $name',
      if (p?.taxId case final tax?) 'Tax ID $tax',
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cloud,
        borderRadius: BorderRadius.circular(AppRadii.stub),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.cargoNavy),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.titleSmall),
                if (detail.isNotEmpty) Text(detail, style: textTheme.bodySmall),
                if (invoiceTo.isNotEmpty)
                  Text(invoiceTo.join(' · '), style: textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends GetView<SellerSubscriptionController> {
  const _PlanCard({required this.plan});
  final SubscriptionPlanModel plan;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final change = controller.changeTo(plan);
    final isCurrent = change.kind == PlanChangeKind.renew;
    final isUpgrade = change.kind == PlanChangeKind.upgrade;
    final gains = change.gains, losses = change.losses;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cloud,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(
            color: isCurrent ? AppColors.manifestGold : AppColors.hairline,
            width: isCurrent ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(plan.name, style: textTheme.titleMedium),
                        if (isCurrent)
                          const StatusBadge(
                              label: 'Current',
                              color: AppColors.manifestGoldDeep),
                        if (plan.isPopular && !isCurrent)
                          const StatusBadge(
                              label: 'Most popular',
                              color: AppColors.cargoNavy),
                      ],
                    ),
                    Text(
                        '${Formatters.currency(plan.priceKes, code: 'KES')} / ${PlanText.period(plan.billingPeriodDays)}',
                        style: textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              isUpgrade
                  ? ElevatedButton(
                      onPressed: () =>
                          showBillingSheet(PayPlanSheet(plan: plan)),
                      child: Text(change.actionLabel))
                  : OutlinedButton(
                      onPressed: () =>
                          showBillingSheet(PayPlanSheet(plan: plan)),
                      child: Text(change.actionLabel)),
            ],
          ),
          if (isCurrent && !plan.isActive)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  'No longer offered to new sellers. You can keep renewing it.',
                  style: textTheme.bodySmall),
            ),
          const SizedBox(height: AppSpacing.xs),
          if (gains.isEmpty && losses.isEmpty)
            Text(PlanText.highlights(plan).join(' · '),
                style: textTheme.bodySmall)
          else ...[
            for (final line in gains) ChangeLine(text: line, isGain: true),
            for (final line in losses) ChangeLine(text: line, isGain: false),
          ],
        ],
      ),
    );
  }
}

class _BillingRow extends StatelessWidget {
  const _BillingRow({required this.entry});
  final BillingHistoryEntryModel entry;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (entry.status) {
      'paid' => ('Paid', AppColors.horizonTealDeep),
      'failed' => ('Failed', AppColors.danger),
      _ => ('Pending', AppColors.slate),
    };
    final when = entry.paidAt ?? entry.createdAt;
    return ManifestStub(
      code: entry.invoiceNumber ?? label.toUpperCase(),
      title:
          '${entry.planName} · ${Formatters.currency(entry.amountKes, code: 'KES')}',
      subtitle: [
        Formatters.date(when),
        if (entry.paymentMethodLabel case final method?) method,
        if (entry.hasInvoice) 'Tap for invoice',
      ].join(' · '),
      accentColor: color,
      onTap: entry.hasInvoice
          ? () => showBillingSheet(InvoiceSheet(entry: entry))
          : null,
      trailing: StatusBadge(label: label, color: color),
    );
  }
}
