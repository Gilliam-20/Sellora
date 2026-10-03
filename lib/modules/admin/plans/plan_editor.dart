import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/plan_text.dart';
import '../../../core/widgets/common.dart';
import '../../../data/models/subscription_plan_model.dart';
import 'admin_plans_controller.dart';
import 'plan_form.dart';

/// Heading over the plan cards, with the way to add one.
class PlansHeader extends StatelessWidget {
  const PlansHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Plans', style: textTheme.titleMedium),
              Text(
                'Charged in KES. Listing and store limits apply at once; an '
                'order limit change reaches each seller at their next payment.',
                style: textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: () => PlanEditor.open(null),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New plan'),
        ),
      ],
    );
  }
}

/// One plan as sellers will see it, with its admin actions.
class PlanSummaryCard extends StatelessWidget {
  const PlanSummaryCard({super.key, required this.plan});
  final SubscriptionPlanModel plan;

  Future<void> _toggleActive() async {
    final controller = Get.find<AdminPlansController>();
    if (plan.isActive) {
      final confirmed = await Get.dialog<bool>(AlertDialog(
        title: Text('Retire ${plan.name}?'),
        content: const Text(
            'New sellers won\'t see it and nobody can switch to it. Sellers '
            'already on it keep it and can still renew.'),
        actions: [
          TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Get.back(result: true),
              child: const Text('Retire')),
        ],
      ));
      if (confirmed != true) return;
    }
    final error = await controller.setActive(plan, !plan.isActive);
    Get.snackbar(plan.name,
        error ?? (plan.isActive ? 'Retired.' : 'Offered to sellers again.'));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final controller = Get.find<AdminPlansController>();
    final customFlags = plan.features.entries
        .where((e) => PlanFeature.byKey(e.key) == null && e.value)
        .map((e) => e.key);
    final usd = plan.priceUsd > 0
        ? '  ·  about ${Formatters.currency(plan.priceUsd, code: 'USD')}'
        : '';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: plan.isActive ? AppColors.cloud : AppColors.mist,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(
            color: plan.isPopular ? AppColors.manifestGold : AppColors.hairline,
            width: plan.isPopular ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(plan.name, style: textTheme.titleMedium),
              Text(plan.id, style: textTheme.bodySmall),
              if (plan.isPopular)
                const StatusBadge(
                    label: 'Most popular', color: AppColors.manifestGoldDeep),
              if (!plan.isActive)
                const StatusBadge(label: 'Retired', color: AppColors.slate),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${Formatters.currency(plan.priceKes, code: 'KES')} per '
            '${PlanText.period(plan.billingPeriodDays)}$usd',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(PlanText.highlights(plan).join('  ·  '),
              style: textTheme.bodySmall),
          if (customFlags.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('Internal flags on: ${customFlags.join(', ')}',
                style: textTheme.bodySmall?.copyWith(color: AppColors.slate)),
          ],
          const SizedBox(height: AppSpacing.sm),
          Obx(() => Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                children: [
                  TextButton(
                    onPressed: controller.isSaving.value ? null : _toggleActive,
                    child: Text(plan.isActive ? 'Retire' : 'Offer again'),
                  ),
                  OutlinedButton(
                    onPressed: controller.isSaving.value
                        ? null
                        : () => PlanEditor.open(plan),
                    child: const Text('Edit'),
                  ),
                ],
              )),
        ],
      ),
    );
  }
}

/// Every configurable field of a plan (TODO.md §16); a new plan when
/// [plan] is null.
class PlanEditor extends StatefulWidget {
  const PlanEditor({super.key, this.plan});
  final SubscriptionPlanModel? plan;

  static void open(SubscriptionPlanModel? plan) =>
      Get.dialog(PlanEditor(plan: plan), barrierDismissible: false);

  @override
  State<PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<PlanEditor> {
  late final PlanForm _form = PlanForm.from(widget.plan);
  late final _id = TextEditingController(text: _form.id);
  late final _name = TextEditingController(text: _form.name);
  late final _kes = TextEditingController(text: _form.priceKes);
  late final _usd = TextEditingController(text: _form.priceUsd);
  late final _period = TextEditingController(text: _form.billingPeriodDays);
  late final _listings = TextEditingController(text: _form.listingLimit);
  late final _orders = TextEditingController(text: _form.orderLimit);
  late final _stores = TextEditingController(text: _form.storeLimit);
  late final _sort = TextEditingController(text: _form.sortOrder);
  late final _perks = TextEditingController(text: _form.perks);
  final _newFlag = TextEditingController();
  String? _error;

  bool get _isNew => widget.plan == null;

  @override
  void dispose() {
    for (final c in [
      _id,
      _name,
      _kes,
      _usd,
      _period,
      _listings,
      _orders,
      _stores,
      _sort,
      _perks,
      _newFlag,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    _form
      ..id = _id.text
      ..name = _name.text
      ..priceKes = _kes.text
      ..priceUsd = _usd.text
      ..billingPeriodDays = _period.text
      ..listingLimit = _listings.text
      ..orderLimit = _orders.text
      ..storeLimit = _stores.text
      ..sortOrder = _sort.text
      ..perks = _perks.text;
    final error =
        await Get.find<AdminPlansController>().savePlan(_form, isNew: _isNew);
    if (!mounted) return;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Get.back();
    Get.snackbar('Plans', '${_name.text.trim()} saved.');
  }

  void _addFlag() {
    final key = _newFlag.text.trim();
    if (key.isEmpty) return;
    if (!PlanForm.flagPattern.hasMatch(key)) {
      setState(() => _error = 'Flag names: letters, digits and _, starting '
          'with a letter (e.g. betaThemes)');
      return;
    }
    setState(() {
      _form.features[key] = true;
      _newFlag.clear();
      _error = null;
    });
  }

  Widget _limitField(String label, TextEditingController ctrl, bool unlimited,
      ValueChanged<bool> onUnlimited) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            enabled: !unlimited,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: label),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Checkbox(value: unlimited, onChanged: (v) => onUnlimited(v ?? false)),
        const Text('Unlimited'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final controller = Get.find<AdminPlansController>();
    final customFlags =
        _form.features.keys.where((k) => PlanFeature.byKey(k) == null).toList();
    const gap = SizedBox(height: AppSpacing.sm);

    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
              child: Text(_isNew ? 'New plan' : 'Edit ${widget.plan!.name}',
                  style: textTheme.titleMedium),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isNew) ...[
                      TextField(
                        controller: _id,
                        decoration: const InputDecoration(
                            labelText: 'ID',
                            helperText: 'Permanent, e.g. "business". '
                                'Lowercase, digits, - or _.'),
                      ),
                      gap,
                    ],
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                    gap,
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _kes,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                                labelText: 'Price (KES, charged)'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: TextField(
                            controller: _usd,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                                labelText: 'Price (USD, shown)'),
                          ),
                        ),
                      ],
                    ),
                    gap,
                    TextField(
                      controller: _period,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Billing period (days)',
                          helperText: '30 is shown to sellers as "month".'),
                    ),
                    const Divider(height: AppSpacing.xl),
                    Text('Limits', style: textTheme.labelLarge),
                    _limitField(
                        'Listed products',
                        _listings,
                        _form.listingUnlimited,
                        (v) => setState(() => _form.listingUnlimited = v)),
                    _limitField(
                        'Paid orders per period',
                        _orders,
                        _form.orderUnlimited,
                        (v) => setState(() => _form.orderUnlimited = v)),
                    _limitField('Stores', _stores, _form.storeUnlimited,
                        (v) => setState(() => _form.storeUnlimited = v)),
                    const Divider(height: AppSpacing.xl),
                    Text('Features', style: textTheme.labelLarge),
                    for (final f in PlanFeature.known)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(f.label),
                        subtitle: f.isBuilt
                            ? null
                            : const Text('Not built yet: sellers see '
                                '"coming soon".'),
                        value: _form.features[f.key] ?? false,
                        onChanged: (v) =>
                            setState(() => _form.features[f.key] = v),
                      ),
                    DropdownButtonFormField<PlanSupportLevel>(
                      value: _form.supportLevel,
                      decoration:
                          const InputDecoration(labelText: 'Support level'),
                      items: [
                        for (final level in PlanSupportLevel.values)
                          DropdownMenuItem(
                              value: level, child: Text(level.label)),
                      ],
                      onChanged: (v) => setState(() =>
                          _form.supportLevel = v ?? PlanSupportLevel.standard),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text('Feature flags', style: textTheme.labelLarge),
                    Text(
                      'Internal switches the app can read per plan. Never '
                      'shown to sellers.',
                      style: textTheme.bodySmall,
                    ),
                    for (final key in customFlags)
                      Row(
                        children: [
                          Expanded(
                            child: SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(key),
                              value: _form.features[key] ?? false,
                              onChanged: (v) =>
                                  setState(() => _form.features[key] = v),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove flag',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () =>
                                setState(() => _form.features.remove(key)),
                          ),
                        ],
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _newFlag,
                            decoration:
                                const InputDecoration(labelText: 'New flag'),
                            onSubmitted: (_) => _addFlag(),
                          ),
                        ),
                        TextButton(
                            onPressed: _addFlag, child: const Text('Add')),
                      ],
                    ),
                    const Divider(height: AppSpacing.xl),
                    TextField(
                      controller: _perks,
                      minLines: 2,
                      maxLines: 6,
                      decoration: const InputDecoration(
                          labelText: 'Extra perks (one per line)',
                          helperText: 'Limits, features and support are '
                              'listed automatically; don\'t repeat them.'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Most popular'),
                      subtitle: const Text(
                          'Highlighted, and preselected in onboarding.'),
                      value: _form.isPopular,
                      onChanged: (v) => setState(() => _form.isPopular = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Offered to sellers'),
                      subtitle: const Text(
                          'Off retires it: current subscribers keep it.'),
                      value: _form.isActive,
                      onChanged: (v) => setState(() => _form.isActive = v),
                    ),
                    TextField(
                      controller: _sort,
                      keyboardType:
                          const TextInputType.numberWithOptions(signed: true),
                      decoration: const InputDecoration(
                          labelText: 'Display order',
                          helperText: 'Lowest first; ties go by price.'),
                    ),
                    gap,
                  ],
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
                child: Text(_error!,
                    style:
                        textTheme.bodySmall?.copyWith(color: AppColors.danger)),
              ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Obx(() => Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                          onPressed: controller.isSaving.value
                              ? null
                              : () => Get.back(),
                          child: const Text('Cancel')),
                      const SizedBox(width: AppSpacing.sm),
                      ElevatedButton(
                        onPressed: controller.isSaving.value ? null : _save,
                        child: Text(_isNew ? 'Create plan' : 'Save'),
                      ),
                    ],
                  )),
            ),
          ],
        ),
      ),
    );
  }
}
