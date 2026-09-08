import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
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
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: controller.plans.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) => _PlanEditCard(plan: controller.plans[index]),
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
  late final TextEditingController _kesCtrl = TextEditingController(text: widget.plan.priceKes.toStringAsFixed(0));
  late final TextEditingController _usdCtrl = TextEditingController(text: widget.plan.priceUsd.toStringAsFixed(0));

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
          Row(
            children: [
              Text(widget.plan.name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: AppSpacing.sm),
              Text('${widget.plan.commissionPercent.toStringAsFixed(0)}% commission', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _kesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Price (KES / month)'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: _usdCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Price (USD / month)'),
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
                        final kes = double.tryParse(_kesCtrl.text) ?? widget.plan.priceKes;
                        final usd = double.tryParse(_usdCtrl.text) ?? widget.plan.priceUsd;
                        controller.updatePrice(widget.plan, kes, usd);
                        Get.snackbar('Saved', '${widget.plan.name} pricing updated to ${Formatters.currency(kes, code: 'KES')}.');
                      },
                child: const Text('Save'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
