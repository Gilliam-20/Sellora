import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/plan_change.dart';
import '../../../core/utils/plan_text.dart';
import '../../../core/utils/validators.dart';
import '../../../data/models/billing_history_entry_model.dart';
import '../../../data/models/billing_profile_model.dart';
import '../../../data/models/subscription_plan_model.dart';
import 'seller_subscription_controller.dart';

/// The bottom sheets the billing page opens: paying for a plan, cancelling,
/// editing the payment method, and viewing an invoice.

/// Centers and caps a sheet's width. A Row (not Center/Align) because the
/// modal gives this a bounded-but-loose height, which Align would expand to
/// fill; a Row's cross axis always hugs its child instead.
class BillingSheetFrame extends StatelessWidget {
  const BillingSheetFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: 480,
                maxHeight: MediaQuery.of(context).size.height * 0.9),
            child: Container(
              decoration: const BoxDecoration(
                  color: AppColors.cloud,
                  borderRadius: BorderRadius.vertical(
                      top: Radius.circular(AppRadii.sheet))),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom),
                child: child,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> showBillingSheet(Widget sheet) {
  Get.find<SellerSubscriptionController>().errorMessage.value = null;
  return Get.bottomSheet(BillingSheetFrame(child: sheet),
      isScrollControlled: true);
}

Widget _errorLine(SellerSubscriptionController controller) => Obx(() {
      final error = controller.errorMessage.value;
      if (error == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(error, style: const TextStyle(color: AppColors.danger)),
      );
    });

Widget _busy() => const SizedBox(
    height: 18,
    width: 18,
    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink));

/// One line of a gains/losses list.
class ChangeLine extends StatelessWidget {
  const ChangeLine({super.key, required this.text, required this.isGain});
  final String text;
  final bool isGain;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isGain ? Icons.check_circle : Icons.remove_circle_outline,
              size: 16,
              color: isGain ? AppColors.horizonTealDeep : AppColors.danger),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pay for a plan
// ---------------------------------------------------------------------------

class PayPlanSheet extends StatefulWidget {
  const PayPlanSheet({super.key, required this.plan});
  final SubscriptionPlanModel plan;

  @override
  State<PayPlanSheet> createState() => _PayPlanSheetState();
}

class _PayPlanSheetState extends State<PayPlanSheet> {
  final _controller = Get.find<SellerSubscriptionController>();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phoneCtrl;
  late BillingPaymentMethod _method;
  late bool _remember;

  @override
  void initState() {
    super.initState();
    final saved = _controller.billingProfile.value;
    _method = saved?.paymentMethod ?? BillingPaymentMethod.mpesa;
    _phoneCtrl = TextEditingController(text: saved?.mpesaPhoneDisplay ?? '');
    _remember = saved == null;
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final plan = widget.plan;
    final change = _controller.changeTo(plan);
    final usage = _controller.usage.value;
    final price = Formatters.currency(plan.priceKes, code: 'KES');
    final title = switch (change.kind) {
      PlanChangeKind.renew => 'Renew ${plan.name}',
      PlanChangeKind.start => 'Choose ${plan.name}',
      _ => '${change.actionLabel} to ${plan.name}',
    };
    final overCap = usage != null &&
        plan.listingLimit >= 0 &&
        usage.listingCount > plan.listingLimit;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.titleMedium),
          const SizedBox(height: 2),
          Text('$price / ${PlanText.period(plan.billingPeriodDays)}',
              style: textTheme.bodySmall),
          if (change.gains.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('What you get', style: textTheme.labelMedium),
            for (final line in change.gains)
              ChangeLine(text: line, isGain: true),
          ],
          if (change.losses.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('What you give up', style: textTheme.labelMedium),
            for (final line in change.losses)
              ChangeLine(text: line, isGain: false),
          ],
          if (overCap) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${plan.name} allows ${plan.listingLimit} listed products and you have '
              '${usage.listingCount}. Unlist ${usage.listingCount - plan.listingLimit} '
              'first, or the payment will be refused.',
              style: textTheme.bodySmall?.copyWith(color: AppColors.danger),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            change.kind == PlanChangeKind.renew
                ? 'Another ${plan.billingPeriodDays} days are added after any paid time you have left.'
                : '${plan.name}\'s limits apply as soon as the payment is confirmed, '
                    'including for any paid time you have left. '
                    '${plan.billingPeriodDays} days are added after that time.',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<BillingPaymentMethod>(
            segments: const [
              ButtonSegment(
                  value: BillingPaymentMethod.mpesa,
                  label: Text('M-Pesa'),
                  icon: Icon(Icons.phone_android)),
              ButtonSegment(
                  value: BillingPaymentMethod.card,
                  label: Text('Card'),
                  icon: Icon(Icons.credit_card)),
            ],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.first),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_method == BillingPaymentMethod.mpesa)
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'M-Pesa phone number', hintText: '07XXXXXXXX'),
              validator: Validators.mpesaPhone,
            )
          else
            Text(
              'You\'ll pay on IntaSend\'s secure card page. Sellora never sees '
              'or stores your card.',
              style: textTheme.bodySmall,
            ),
          CheckboxListTile(
            value: _remember,
            onChanged: (v) => setState(() => _remember = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: const Text('Save as my payment method'),
          ),
          _errorLine(_controller),
          Obx(
            () => SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _controller.isPaying.value
                    ? null
                    : () {
                        if (!_formKey.currentState!.validate()) return;
                        _controller.pay(
                          plan,
                          method: _method,
                          mpesaPhone: _phoneCtrl.text.trim(),
                          rememberMethod: _remember,
                        );
                      },
                child:
                    _controller.isPaying.value ? _busy() : Text('Pay $price'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cancel
// ---------------------------------------------------------------------------

class CancelPlanSheet extends StatefulWidget {
  const CancelPlanSheet({super.key});

  @override
  State<CancelPlanSheet> createState() => _CancelPlanSheetState();
}

class _CancelPlanSheetState extends State<CancelPlanSheet> {
  static const _reasons = [
    'Too expensive',
    'Not enough sales',
    'Missing a feature I need',
    'Moving to another platform',
    'Taking a break',
  ];
  final _controller = Get.find<SellerSubscriptionController>();
  final _otherCtrl = TextEditingController();
  String? _reason;

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final plan = _controller.currentPlan;
    final end = _controller.usage.value?.currentPeriodEnd;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cancel ${plan?.name ?? 'your plan'}?',
            style: textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${end == null ? 'Your plan stays active until the end of the period you paid for' : 'Your plan stays active until ${Formatters.date(end)}'}, '
          'and you won\'t be reminded to renew. After that your store stops taking '
          'orders until you renew. Your products, store and order history are kept.',
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Why are you cancelling? (optional)',
            style: textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final r in _reasons)
              ChoiceChip(
                label: Text(r),
                selected: _reason == r,
                onSelected: (on) => setState(() => _reason = on ? r : null),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _otherCtrl,
          maxLength: 300,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Anything else?'),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                  onPressed: Get.back, child: const Text('Keep my plan')),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Obx(
                () => ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: AppColors.cloud),
                  onPressed: _controller.isChangingStatus.value
                      ? null
                      : () => _controller.cancel(
                          reason: [_reason, _otherCtrl.text.trim()]
                              .whereType<String>()
                              .where((s) => s.isNotEmpty)
                              .join('. ')),
                  child: _controller.isChangingStatus.value
                      ? _busy()
                      : const Text('Cancel plan'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Payment method and invoice details
// ---------------------------------------------------------------------------

class PaymentMethodSheet extends StatefulWidget {
  const PaymentMethodSheet({super.key});

  @override
  State<PaymentMethodSheet> createState() => _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends State<PaymentMethodSheet> {
  final _controller = Get.find<SellerSubscriptionController>();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phoneCtrl, _nameCtrl, _taxCtrl;
  late BillingPaymentMethod _method;

  @override
  void initState() {
    super.initState();
    final saved = _controller.billingProfile.value;
    _method = saved?.paymentMethod ?? BillingPaymentMethod.mpesa;
    _phoneCtrl = TextEditingController(text: saved?.mpesaPhoneDisplay ?? '');
    _nameCtrl = TextEditingController(text: saved?.billingName ?? '');
    _taxCtrl = TextEditingController(text: saved?.taxId ?? '');
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    _taxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payment method', style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Plans don\'t renew automatically. This is what we suggest each '
            'time you pay; you can change it then too.',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<BillingPaymentMethod>(
            segments: const [
              ButtonSegment(
                  value: BillingPaymentMethod.mpesa,
                  label: Text('M-Pesa'),
                  icon: Icon(Icons.phone_android)),
              ButtonSegment(
                  value: BillingPaymentMethod.card,
                  label: Text('Card'),
                  icon: Icon(Icons.credit_card)),
            ],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.first),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'M-Pesa phone number',
              hintText: '07XXXXXXXX',
              helperText: _method == BillingPaymentMethod.card
                  ? 'Optional. Kept for when you pay by M-Pesa.'
                  : null,
            ),
            validator: (v) =>
                _method == BillingPaymentMethod.card && (v ?? '').trim().isEmpty
                    ? null
                    : Validators.mpesaPhone(v),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('On your invoices', style: textTheme.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          TextFormField(
            controller: _nameCtrl,
            maxLength: 120,
            decoration: const InputDecoration(
                labelText: 'Billing name',
                helperText: 'Your business name. Leave empty to use your own.'),
          ),
          TextFormField(
            controller: _taxCtrl,
            maxLength: 40,
            decoration: const InputDecoration(
                labelText: 'Tax ID (optional)', hintText: 'e.g. KRA PIN'),
          ),
          const SizedBox(height: AppSpacing.sm),
          _errorLine(_controller),
          Obx(
            () => SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _controller.isSavingProfile.value
                    ? null
                    : () async {
                        if (!_formKey.currentState!.validate()) return;
                        final saved = await _controller.saveBillingProfile(
                          method: _method,
                          mpesaPhone: _phoneCtrl.text,
                          billingName: _nameCtrl.text,
                          taxId: _taxCtrl.text,
                        );
                        if (saved) {
                          Get.back();
                          Get.snackbar(
                              'Saved', 'Your billing details are up to date.');
                        }
                      },
                child: _controller.isSavingProfile.value
                    ? _busy()
                    : const Text('Save'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Invoice
// ---------------------------------------------------------------------------

class InvoiceSheet extends StatelessWidget {
  const InvoiceSheet({super.key, required this.entry});
  final BillingHistoryEntryModel entry;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SellerSubscriptionController>();
    final invoice = controller.invoiceFor(entry);
    final textTheme = Theme.of(context).textTheme;
    Widget field(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: textTheme.labelMedium),
              Text(value, style: textTheme.bodyMedium),
            ],
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: Text('Invoice ${invoice.number}',
                    style: textTheme.titleMedium)),
            Text('PAID',
                style: textTheme.labelMedium?.copyWith(
                    color: AppColors.horizonTealDeep,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        Text('Issued ${Formatters.date(invoice.issuedOn)}',
            style: textTheme.bodySmall),
        const Divider(height: AppSpacing.lg),
        field(
            'Billed to',
            [
              invoice.billedTo,
              if (invoice.email.isNotEmpty) invoice.email,
              if (invoice.taxId != null) 'Tax ID: ${invoice.taxId}',
            ].join('\n')),
        field('Description', 'Sellora subscription: ${invoice.description}'),
        field('Paid with', invoice.paidWith),
        const Divider(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(child: Text('Total paid', style: textTheme.titleSmall)),
            Text(Formatters.currency(entry.amountKes, code: 'KES'),
                style: textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => controller.downloadInvoice(entry),
            icon: const Icon(Icons.download),
            label: const Text('Download PDF'),
          ),
        ),
      ],
    );
  }
}
