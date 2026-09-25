import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/i18n/countries.dart';
import '../../../core/i18n/currencies.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../data/models/store_model.dart';
import '../../../data/models/subscription_plan_model.dart';
import '../controllers/seller_onboarding_controller.dart';

class SellerOnboardingView extends GetView<SellerOnboardingController> {
  const SellerOnboardingView({super.key});

  static const _titles = {
    OnboardingStep.storeSetup: 'Set up your store',
    OnboardingStep.choosePlan: 'Choose your plan',
    OnboardingStep.pay: 'Activate your plan',
    OnboardingStep.pendingConfirmation: 'Confirming payment',
  };

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final step = controller.step.value;
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: controller.previousStep == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back',
                  onPressed: controller.goBack,
                ),
          title: Text(_titles[step]!),
          actions: [
            if (step.index < OnboardingStep.pendingConfirmation.index)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: Text('Step ${step.index + 1} of 3',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
          ],
        ),
        body: _body(),
      );
    });
  }

  Widget _body() {
    if (controller.isLoading.value) return const SelloraLoader();
    if (controller.plans.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'We couldn\'t load onboarding',
        message: controller.errorMessage.value ??
            'Check your connection and try again.',
        actionLabel: 'Try again',
        onAction: controller.retryLoad,
      );
    }
    switch (controller.step.value) {
      case OnboardingStep.storeSetup:
        return const _StoreSetupStep();
      case OnboardingStep.choosePlan:
        return const _PlanStep();
      case OnboardingStep.pay:
        return const _PaymentStep();
      case OnboardingStep.pendingConfirmation:
        return const _PendingConfirmationStep();
    }
  }
}

/// Step 1 — the store profile the build spec's §33 asks for (name, category,
/// country, currency). Saving creates the store if the seller has none.
class _StoreSetupStep extends StatefulWidget {
  const _StoreSetupStep();

  @override
  State<_StoreSetupStep> createState() => _StoreSetupStepState();
}

class _StoreSetupStepState extends State<_StoreSetupStep> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  final controller = Get.find<SellerOnboardingController>();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: controller.storeName.value);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slug = controller.store.value?.slug;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
                horizontal: context.pageHorizontalPadding,
                vertical: AppSpacing.lg),
            child: ResponsiveCenter(
              maxWidth: 520,
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tell us about your store',
                        style: Theme.of(context).textTheme.displaySmall),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'This sets your storefront\'s defaults. You can change '
                      'any of it later.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const _VerifyEmailBanner(),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Store name',
                        helperText: slug == null
                            ? null
                            : 'Your address stays sellora.app/s/$slug',
                      ),
                      onChanged: (v) => controller.storeName.value = v,
                      validator: (v) => (v ?? '').trim().length < 2
                          ? 'Enter your store\'s name'
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Obx(() => DropdownButtonFormField<String>(
                          value: controller.category.value,
                          decoration: const InputDecoration(
                              labelText: 'What do you sell?'),
                          items: [
                            for (final e in StoreCategories.all.entries)
                              DropdownMenuItem(
                                  value: e.key, child: Text(e.value)),
                          ],
                          onChanged: (v) => controller.category.value = v,
                          validator: (v) =>
                              v == null ? 'Pick a category' : null,
                        )),
                    const SizedBox(height: AppSpacing.md),
                    Obx(() => DropdownButtonFormField<String>(
                          value: controller.countryCode.value,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Where is your business based?'),
                          items: [
                            for (final c
                                in Countries.forZones(ShippingZone.values))
                              DropdownMenuItem(
                                  value: c.code, child: Text(c.name)),
                          ],
                          onChanged: (v) {
                            if (v != null) controller.selectCountry(v);
                          },
                        )),
                    const SizedBox(height: AppSpacing.md),
                    // Keyed on the value so a country change that resets
                    // the currency rebuilds the field with the new value.
                    Obx(() => DropdownButtonFormField<String>(
                          key: ValueKey(controller.currencyCode.value),
                          value: controller.currencyCode.value,
                          decoration: const InputDecoration(
                              labelText: 'Store currency',
                              helperText:
                                  'The currency your prices are shown in.'),
                          items: [
                            for (final c in Currencies.all)
                              DropdownMenuItem(
                                  value: c.code,
                                  child: Text('${c.code} — ${c.name}')),
                          ],
                          onChanged: (v) {
                            if (v != null) controller.currencyCode.value = v;
                          },
                        )),
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
            label: 'Continue',
            isLoading: controller.isSavingStore.value,
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                controller.saveStoreSetup();
              }
            },
          ),
        ),
      ],
    );
  }
}

/// Sign-up sends a verification email; this reminds the seller and lets
/// them resend it. Verification isn't required to continue yet.
class _VerifyEmailBanner extends GetView<SellerOnboardingController> {
  const _VerifyEmailBanner();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isEmailVerified.value) return const SizedBox.shrink();
      final sent = controller.verificationSent.value;
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.mist,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.mark_email_unread_outlined,
                    color: AppColors.manifestGoldDeep, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text('Verify your email',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              sent
                  ? 'We sent a new link to ${controller.email ?? 'your inbox'}.'
                  : 'We sent a link to ${controller.email ?? 'your inbox'}. '
                      'Verifying keeps your account recoverable.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                TextButton(
                  onPressed: controller.checkEmailVerified,
                  child: const Text('I\'ve verified'),
                ),
                if (!sent)
                  TextButton(
                    onPressed: controller.resendVerification,
                    child: const Text('Resend link'),
                  ),
              ],
            ),
          ],
        ),
      );
    });
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

class _PendingConfirmationStep extends GetView<SellerOnboardingController> {
  const _PendingConfirmationStep();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ResponsiveCenter(
        maxWidth: 440,
        child: Padding(
          padding:
              EdgeInsets.symmetric(horizontal: context.pageHorizontalPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_top,
                  size: 48, color: AppColors.manifestGoldDeep),
              const SizedBox(height: AppSpacing.md),
              Text('Confirming your payment',
                  style: Theme.of(context).textTheme.displaySmall,
                  textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Complete the M-Pesa prompt on your phone. Once we receive confirmation, your plan activates automatically — or tap below to check now.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              Obx(() => FilledButton(
                    onPressed: controller.isRefreshing.value
                        ? null
                        : controller.refreshStatus,
                    child: controller.isRefreshing.value
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('I\'ve completed payment'),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
