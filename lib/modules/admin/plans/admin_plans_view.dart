import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../data/models/fee_settings.dart';
import '../../../data/models/subscription_plan_model.dart';
import 'admin_plans_controller.dart';

class AdminPlansView extends GetView<AdminPlansController> {
  const AdminPlansView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Subscription plans')),
      body: Obx(() {
        if (controller.isLoading.value) return const SelloraLoader();
        return ResponsiveCenter(
          maxWidth: 720,
          child: ListView.separated(
            padding: EdgeInsets.symmetric(
                horizontal: context.pageHorizontalPadding,
                vertical: AppSpacing.lg),
            // The service fee card, then one card per plan.
            itemCount: controller.plans.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) => index == 0
                ? const _ServiceFeeCard()
                : _PlanEditCard(plan: controller.plans[index - 1]),
          ),
        );
      }),
    );
  }
}

/// Sellora's fee on each sale (TODO.md §15). A change applies to orders
/// placed afterwards; every order keeps the rate it was charged.
class _ServiceFeeCard extends StatefulWidget {
  const _ServiceFeeCard();

  @override
  State<_ServiceFeeCard> createState() => _ServiceFeeCardState();
}

class _ServiceFeeCardState extends State<_ServiceFeeCard> {
  final _rateCtrl = TextEditingController();
  bool _chargeOnShipping = false;
  Worker? _worker;

  AdminPlansController get controller => Get.find<AdminPlansController>();

  @override
  void initState() {
    super.initState();
    _apply(controller.fees.value);
    _worker = ever<FeeSettings?>(
        controller.fees, (fees) => setState(() => _apply(fees)));
  }

  void _apply(FeeSettings? fees) {
    if (fees == null) return;
    _rateCtrl.text = fees.percentLabel;
    _chargeOnShipping = fees.chargeOnShipping;
  }

  @override
  void dispose() {
    _worker?.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final percent = double.tryParse(_rateCtrl.text.trim());
    if (percent == null) {
      Get.snackbar('Service fee', 'Enter the rate as a number, e.g. 7');
      return;
    }
    final confirmed = await Get.dialog<bool>(AlertDialog(
      title: const Text('Change the service fee?'),
      content: Text(
          'New orders will be charged $percent%'
          '${_chargeOnShipping ? ' of products and shipping' : ' of products only'}. '
          'Orders already placed keep the fee they were charged. Listings '
          'priced close to cost may stop covering it.'),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Change fee')),
      ],
    ));
    if (confirmed != true) return;
    final error = await controller.saveFees(
        percent: percent, chargeOnShipping: _chargeOnShipping);
    Get.snackbar('Service fee', error ?? 'Saved. It applies to new orders.');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cloud,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Obx(() {
        final error = controller.feeError.value;
        final loaded = controller.fees.value != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Service fee on sales', style: textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Taken from the seller\'s share of every paid order. Each order '
              'keeps the rate it was placed at.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            if (error != null)
              Row(
                children: [
                  Expanded(child: Text(error, style: textTheme.bodySmall)),
                  TextButton(
                      onPressed: controller.loadFees,
                      child: const Text('Retry')),
                ],
              )
            else if (!loaded)
              const SelloraLoader(size: 24)
            else ...[
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _rateCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Rate', suffixText: '%'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _chargeOnShipping,
                onChanged: (value) =>
                    setState(() => _chargeOnShipping = value),
                title: const Text('Also charge it on shipping'),
                subtitle: const Text(
                    'Off: products only, never shipping or tax.'),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed:
                      controller.isSavingFees.value ? null : _save,
                  child: const Text('Save fee'),
                ),
              ),
            ],
          ],
        );
      }),
    );
  }
}

class _PlanEditCard extends StatefulWidget {
  const _PlanEditCard({required this.plan});
  final SubscriptionPlanModel plan;

  @override
  State<_PlanEditCard> createState() => _PlanEditCardState();
}

class _PlanEditCardState extends State<_PlanEditCard> {
  late final TextEditingController _kesCtrl =
      TextEditingController(text: widget.plan.priceKes.toStringAsFixed(0));
  late final TextEditingController _usdCtrl =
      TextEditingController(text: widget.plan.priceUsd.toStringAsFixed(0));
  late final TextEditingController _orderLimitCtrl = TextEditingController(
      text: widget.plan.orderLimit.toString());
  late final TextEditingController _storeLimitCtrl = TextEditingController(
      text: widget.plan.storeLimit.toString());
  late bool _customDomain = widget.plan.features['customDomain'] ?? false;
  late bool _advancedAnalytics =
      widget.plan.features['advancedAnalytics'] ?? false;

  @override
  void dispose() {
    _kesCtrl.dispose();
    _usdCtrl.dispose();
    _orderLimitCtrl.dispose();
    _storeLimitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AdminPlansController>();
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
          Text(widget.plan.name,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _kesCtrl,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Price (KES / month)'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: _usdCtrl,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Price (USD / month)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: Obx(
              () => TextButton(
                onPressed: controller.isSaving.value
                    ? null
                    : () {
                        final kes = double.tryParse(_kesCtrl.text) ??
                            widget.plan.priceKes;
                        final usd = double.tryParse(_usdCtrl.text) ??
                            widget.plan.priceUsd;
                        controller.updatePrice(widget.plan, kes, usd);
                        Get.snackbar('Saved',
                            '${widget.plan.name} pricing updated to ${Formatters.currency(kes, code: 'KES')}.');
                      },
                child: const Text('Save'),
              ),
            ),
          ),
          const Divider(height: AppSpacing.lg),
          Text('Limits (not yet enforced)',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _orderLimitCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Orders / month (-1 = unlimited)'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: _storeLimitCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Stores (-1 = unlimited)'),
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Custom domain'),
            value: _customDomain,
            onChanged: (v) => setState(() => _customDomain = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Advanced analytics'),
            value: _advancedAnalytics,
            onChanged: (v) => setState(() => _advancedAnalytics = v),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Obx(
              () => TextButton(
                onPressed: controller.isSaving.value
                    ? null
                    : () {
                        final orderLimit =
                            int.tryParse(_orderLimitCtrl.text) ??
                                widget.plan.orderLimit;
                        final storeLimit =
                            int.tryParse(_storeLimitCtrl.text) ??
                                widget.plan.storeLimit;
                        controller.updateLimitsAndFeatures(
                          widget.plan,
                          orderLimit: orderLimit,
                          storeLimit: storeLimit,
                          features: {
                            'customDomain': _customDomain,
                            'advancedAnalytics': _advancedAnalytics,
                          },
                        );
                        Get.snackbar(
                            'Saved', '${widget.plan.name} limits updated.');
                      },
                child: const Text('Save limits & features'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
