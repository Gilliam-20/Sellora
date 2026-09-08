import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/common.dart';
import '../../../data/models/subscription_plan_model.dart';
import '../controllers/seller_onboarding_controller.dart';

class SellerOnboardingView extends GetView<SellerOnboardingController> {
  const SellerOnboardingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose your plan')),
      body: Obx(() {
        if (controller.isLoadingPlans.value) return const SelloraLoader();
        return controller.step.value == OnboardingStep.choosePlan
            ? const _PlanStep()
            : const _PaymentStep();
      }),
    );
  }
}

class _PlanStep extends GetView<SellerOnboardingController> {
  const _PlanStep();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ResponsiveCenter(
            maxWidth: 640,
            child: ListView.separated(
              padding: EdgeInsets.symmetric(
                  horizontal: context.pageHorizontalPadding,
                  vertical: AppSpacing.lg),
              itemCount: controller.plans.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) {
                final plan = controller.plans[index];
                return Obx(() => _PlanCard(
                      plan: plan,
                      isSelected: controller.selectedPlanId.value == plan.id,
                      onTap: () => controller.selectPlan(plan.id),
                    ));
              },
            ),
          ),
        ),
        BottomActionBar(
            label: 'Continue to payment', onPressed: controller.goToPayment),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard(
      {required this.plan, required this.isSelected, required this.onTap});

  final SubscriptionPlanModel plan;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cloud,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(
                color: isSelected ? AppColors.manifestGold : AppColors.hairline,
                width: isSelected ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(plan.name,
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  if (plan.isPopular)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: AppColors.manifestGold,
                          borderRadius:
                              BorderRadius.circular(AppRadii.control)),
                      child: Text('Most popular',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                  color: AppColors.ink,
                                  fontWeight: FontWeight.w700)),
                    ),
                  if (isSelected)
                    const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.check_circle,
                            color: AppColors.manifestGoldDeep)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(Formatters.currency(plan.priceKes, code: 'KES'),
                      style: Theme.of(context)
                          .textTheme
                          .displaySmall
                          ?.copyWith(fontSize: 22)),
                  Text(' / month',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ...plan.perks.map(
                (perk) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.check,
                          size: 16, color: AppColors.horizonTealDeep),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(perk,
                              style: Theme.of(context).textTheme.bodySmall)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentStep extends StatefulWidget {
  const _PaymentStep();

  @override
  State<_PaymentStep> createState() => _PaymentStepState();
}

class _PaymentStepState extends State<_PaymentStep> {
  // Was created inline in build() as a plain (const) widget, which
  // happened to be safe only because it had no parameters and so was
  // never actually rebuilt in place — fragile, and the first field
  // added here (as happened with the responsive pass elsewhere in this
  // screen) would have silently reintroduced the wipe-on-rebuild bug.
  // Owning it in State sidesteps the question entirely.
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SellerOnboardingController>();
    final plan = controller.selectedPlan;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
                horizontal: context.pageHorizontalPadding,
                vertical: AppSpacing.lg),
            child: ResponsiveCenter(
              maxWidth: 440,
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pay with M-Pesa',
                        style: Theme.of(context).textTheme.displaySmall),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'You\'ll get an STK push from IntaSend for ${Formatters.currency(plan?.priceKes ?? 0, code: 'KES')} — enter your PIN to confirm.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                          labelText: 'M-Pesa phone number',
                          hintText: '07XXXXXXXX'),
                      validator: Validators.mpesaPhone,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Obx(() {
                      final error = controller.errorMessage.value;
                      if (error == null) return const SizedBox.shrink();
                      return Text(error,
                          style: const TextStyle(color: AppColors.danger));
                    }),
                  ],
                ),
              ),
            ),
          ),
        ),
        Obx(
          () => BottomActionBar(
            label: 'Pay & activate',
            isLoading: controller.isPaying.value,
            trailingText: Formatters.currency(plan?.priceKes ?? 0, code: 'KES'),
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                controller.payWithMpesa(_phoneCtrl.text.trim());
              }
            },
          ),
        ),
      ],
    );
  }
}
