import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/common.dart';
import '../../../data/models/billing_history_entry_model.dart';
import '../../../data/models/subscription_plan_model.dart';
import '../../../data/models/subscription_usage_model.dart';
import 'seller_subscription_controller.dart';

class SellerSubscriptionView extends GetView<SellerSubscriptionController> {
  const SellerSubscriptionView({super.key});

  @override
  Widget build(BuildContext context) {
    final user = controller.authRepo.cachedUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Subscription')),
      body: Obx(() {
        if (controller.isLoading.value) return const SelloraLoader();
        final current = controller.currentPlan;
        return ResponsiveCenter(
          maxWidth: 640,
          child: ListView(
            padding: EdgeInsets.symmetric(
                horizontal: context.pageHorizontalPadding,
                vertical: AppSpacing.lg),
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.cargoNavy,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Current plan',
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: AppColors.slateLight)),
                    const SizedBox(height: 4),
                    Text(current?.name ?? 'None',
                        style: Theme.of(context)
                            .textTheme
                            .displaySmall
                            ?.copyWith(color: AppColors.cloud, fontSize: 24)),
                    const SizedBox(height: 4),
                    if (_periodLine(controller.usage.value,
                            user?.subscriptionActiveUntil)
                        case final line?)
                      Text(
                        line,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.slateLight),
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
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
                    ),
                  ],
                ),
              ),
              if (controller.usage.value != null) ...[
                const SizedBox(height: AppSpacing.md),
                _UsageCard(usage: controller.usage.value!),
              ],
              const SizedBox(height: AppSpacing.lg),
              Text('Available plans',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              ...controller.plans.map(
                (plan) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child:
                      _PlanRow(plan: plan, isCurrent: plan.id == current?.id),
                ),
              ),
              if (controller.history.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text('Billing history',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                ...controller.history.map((e) => _BillingRow(entry: e)),
              ],
            ],
          ),
        );
      }),
    );
  }

  /// There's no automatic renewal (each period is an M-Pesa payment the
  /// seller makes), so this says when the paid time ends, not "renews".
  static String? _periodLine(
      SubscriptionUsageModel? usage, DateTime? profileUntil) {
    final end = usage?.currentPeriodEnd ?? profileUntil;
    if (end == null) return null;
    return switch (usage?.subscriptionStatus) {
      'lapsed' => 'Ended ${Formatters.date(end)}. Renew to keep selling.',
      'cancelled' => 'Cancelled',
      _ => 'Paid through ${Formatters.date(end)}',
    };
  }
}

class _BillingRow extends StatelessWidget {
  const _BillingRow({required this.entry});
  final BillingHistoryEntryModel entry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final (label, color) = switch (entry.status) {
      'paid' => ('Paid', AppColors.horizonTealDeep),
      'failed' => ('Failed', AppColors.danger),
      _ => ('Pending', AppColors.slate),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.planName, style: textTheme.bodyMedium),
                Text(Formatters.date(entry.paidAt ?? entry.createdAt),
                    style: textTheme.bodySmall),
              ],
            ),
          ),
          Text(Formatters.currency(entry.amountKes, code: 'KES'),
              style: textTheme.bodyMedium),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 64,
            child: Text(label,
                textAlign: TextAlign.end,
                style: textTheme.labelMedium?.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.usage});
  final SubscriptionUsageModel usage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cloud,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Usage this period',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 2),
                for (final line in [
                  _usageLine(usage.listingCount, usage.listingLimit,
                      'products listed'),
                  _usageLine(usage.orderCount, usage.orderLimit,
                      'paid orders in the last ${usage.billingPeriodDays} days'),
                  _usageLine(usage.storeCount, usage.storeLimit, 'stores'),
                ])
                  Text(line, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _usageLine(int used, int limit, String what) =>
    limit < 0 ? '$used $what (unlimited)' : '$used of $limit $what';

String _limit(int limit, String what) =>
    limit < 0 ? 'Unlimited $what' : '$limit $what';

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.plan, required this.isCurrent});
  final SubscriptionPlanModel plan;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cloud,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(
            color: isCurrent ? AppColors.manifestGold : AppColors.hairline,
            width: isCurrent ? 2 : 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.name, style: Theme.of(context).textTheme.titleMedium),
                Text(
                    '${Formatters.currency(plan.priceKes, code: 'KES')} / ${plan.billingPeriodDays} days',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(
                  [
                    _limit(plan.listingLimit, 'listings'),
                    _limit(plan.orderLimit, 'orders'),
                    _limit(plan.storeLimit,
                        plan.storeLimit == 1 ? 'store' : 'stores'),
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          OutlinedButton(
              onPressed: () => Get.bottomSheet(
                  _SwitchPlanSheet(plan: plan, isRenewal: isCurrent),
                  isScrollControlled: true),
              child: Text(isCurrent ? 'Renew' : 'Switch')),
        ],
      ),
    );
  }
}

class _SwitchPlanSheet extends StatefulWidget {
  const _SwitchPlanSheet({required this.plan, this.isRenewal = false});
  final SubscriptionPlanModel plan;

  /// Paying for the plan already held: another period, added to the end.
  final bool isRenewal;

  @override
  State<_SwitchPlanSheet> createState() => _SwitchPlanSheetState();
}

class _SwitchPlanSheetState extends State<_SwitchPlanSheet> {
  final _phoneCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SellerSubscriptionController>();

    // A Row (not Center/Align) centers and caps the sheet's width: the
    // modal gives this a bounded-but-loose height, which Align would
    // expand to fill; a Row's cross axis always hugs its child instead.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom),
              decoration: const BoxDecoration(
                  color: AppColors.cloud,
                  borderRadius: BorderRadius.vertical(
                      top: Radius.circular(AppRadii.sheet))),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        widget.isRenewal
                            ? 'Renew ${widget.plan.name}'
                            : 'Switch to ${widget.plan.name}',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'You\'ll be charged ${Formatters.currency(widget.plan.priceKes, code: 'KES')} now via M-Pesa. '
                      '${widget.isRenewal ? 'Another' : 'The new plan starts once you pay, and a'} '
                      '${widget.plan.billingPeriodDays}-day period is added after any paid time you have left.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                          labelText: 'M-Pesa phone number',
                          hintText: '07XXXXXXXX'),
                      validator: Validators.mpesaPhone,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Obx(() {
                      final error = controller.errorMessage.value;
                      if (error == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Text(error,
                            style: const TextStyle(color: AppColors.danger)),
                      );
                    }),
                    Obx(
                      () => SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: controller.isPaying.value
                              ? null
                              : () {
                                  if (_formKey.currentState!.validate()) {
                                    controller.switchPlan(
                                        widget.plan, _phoneCtrl.text.trim());
                                  }
                                },
                          child: controller.isPaying.value
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: AppColors.ink))
                              : Text(widget.isRenewal
                                  ? 'Pay & renew'
                                  : 'Pay & switch'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
