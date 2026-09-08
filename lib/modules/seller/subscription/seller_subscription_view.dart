import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/common.dart';
import '../../../data/models/subscription_plan_model.dart';
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
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
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
                  Text('Current plan', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.slateLight)),
                  const SizedBox(height: 4),
                  Text(current?.name ?? 'None', style: Theme.of(context).textTheme.displaySmall?.copyWith(color: AppColors.cloud, fontSize: 24)),
                  const SizedBox(height: 4),
                  if (user?.subscriptionActiveUntil != null)
                    Text(
                      'Renews ${Formatters.date(user!.subscriptionActiveUntil!)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.slateLight),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Available plans', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            ...controller.plans.map(
              (plan) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _PlanRow(plan: plan, isCurrent: plan.id == current?.id),
              ),
            ),
          ],
        );
      }),
    );
  }
}

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
        border: Border.all(color: isCurrent ? AppColors.manifestGold : AppColors.hairline, width: isCurrent ? 2 : 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.name, style: Theme.of(context).textTheme.titleMedium),
                Text('${Formatters.currency(plan.priceKes, code: 'KES')} / month', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (isCurrent)
            const Text('Active', style: TextStyle(color: AppColors.horizonTealDeep, fontWeight: FontWeight.w700))
          else
            OutlinedButton(onPressed: () => _showSwitchSheet(context, plan), child: const Text('Switch')),
        ],
      ),
    );
  }

  void _showSwitchSheet(BuildContext context, SubscriptionPlanModel plan) {
    final controller = Get.find<SellerSubscriptionController>();
    final phoneCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    Get.bottomSheet(
      Container(
        padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom),
        decoration: const BoxDecoration(color: AppColors.cloud, borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheet))),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Switch to ${plan.name}', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'You\'ll be charged ${Formatters.currency(plan.priceKes, code: 'KES')} now via M-Pesa.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'M-Pesa phone number', hintText: '07XXXXXXXX'),
                validator: Validators.mpesaPhone,
              ),
              const SizedBox(height: AppSpacing.lg),
              Obx(
                () => SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: controller.isPaying.value
                        ? null
                        : () {
                            if (formKey.currentState!.validate()) {
                              controller.switchPlan(plan, phoneCtrl.text.trim());
                            }
                          },
                    child: controller.isPaying.value
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink))
                        : const Text('Pay & switch'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }
}
