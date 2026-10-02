import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/store_link.dart';
import '../../../core/widgets/app_page.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/manifest_stub.dart';
import '../../../data/models/discount_model.dart';
import 'seller_marketing_controller.dart';

/// Discount codes (create, switch off, edit, delete) and a shareable link
/// to the storefront.
class SellerMarketingView extends GetView<SellerMarketingController> {
  const SellerMarketingView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Marketing',
      subtitle: 'Discount codes and links to share your store.',
      actions: [
        FilledButton.icon(
          onPressed: () => _openEditor(context, null),
          icon: const Icon(Icons.add),
          label: const Text('New code'),
        ),
      ],
      child: Obx(() {
        if (controller.isLoading.value) {
          return const AppLoadingState(label: 'Loading your codes…');
        }
        final error = controller.errorMessage.value;
        if (error != null) {
          return AppErrorState(message: error, onRetry: controller.load);
        }
        return RefreshIndicator(
          onRefresh: controller.load,
          child: ListView(
            children: [
              _ShareCard(controller: controller),
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader(title: 'Discount codes'),
              const SizedBox(height: AppSpacing.sm),
              if (controller.discounts.isEmpty)
                EmptyState(
                  icon: Icons.local_offer_outlined,
                  title: 'No discount codes yet',
                  message: 'Create a code to give customers a percentage or '
                      'a fixed amount off. You fund it from your margin.',
                  actionLabel: 'Create a code',
                  onAction: () => _openEditor(context, null),
                )
              else
                for (final discount in controller.discounts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _DiscountStub(
                      discount: discount,
                      controller: controller,
                      onTap: () => _openEditor(context, discount),
                    ),
                  ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        );
      }),
    );
  }

  void _openEditor(BuildContext context, DiscountModel? discount) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) =>
          _DiscountEditor(controller: controller, initial: discount),
    );
  }
}

class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.controller});

  final SellerMarketingController controller;

  @override
  Widget build(BuildContext context) {
    final link = controller.storeLink;
    if (link == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Share your store',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text('Post your storefront link wherever your customers are.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: SelectableText(link.toString(),
                      maxLines: 1,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: link.toString()));
                    Get.snackbar(
                        'Link copied', 'Your store link is ready to paste.');
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final entry
                    in shareLinks(link, controller.shareMessage).entries)
                  ActionChip(
                    avatar: const Icon(Icons.share_outlined, size: 16),
                    label: Text(entry.key),
                    onPressed: () => launchUrl(entry.value,
                        mode: LaunchMode.externalApplication),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscountStub extends StatelessWidget {
  const _DiscountStub(
      {required this.discount, required this.controller, required this.onTap});

  final DiscountModel discount;
  final SellerMarketingController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = controller.statusOf(discount);
    final uses = controller.usesOf(discount);
    final color = _statusColor(status);
    final details = [
      discount.usageLimit == null
          ? '$uses used'
          : '$uses of ${discount.usageLimit} used',
      if (discount.minSubtotal > 0)
        'min USD ${discount.minSubtotal.toStringAsFixed(2)}',
      if (discount.productIds.isNotEmpty)
        '${discount.productIds.length} product${discount.productIds.length == 1 ? '' : 's'}',
      if (discount.endsAt != null) 'ends ${Formatters.date(discount.endsAt!)}',
      if (discount.oncePerCustomer) 'once per customer',
    ].join(' · ');
    return ManifestStub(
      code: discount.code,
      title: discount.summary,
      subtitle: details,
      accentColor: color,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusBadge(label: status.label, color: color),
          Switch(
            value: discount.isActive,
            onChanged: (on) async {
              final error = await controller.setActive(discount, on);
              if (error != null) Get.snackbar('Not saved', error);
            },
          ),
        ],
      ),
    );
  }

  static Color _statusColor(DiscountStatus status) => switch (status) {
        DiscountStatus.active => AppColors.success,
        DiscountStatus.scheduled => AppColors.info,
        DiscountStatus.ended || DiscountStatus.usedUp => AppColors.slate,
        DiscountStatus.off => AppColors.slateLight,
      };
}

/// Create or edit one code. Mirrors the `discounts` table's checks via
/// [SellerMarketingController.validate].
class _DiscountEditor extends StatefulWidget {
  const _DiscountEditor({required this.controller, this.initial});

  final SellerMarketingController controller;
  final DiscountModel? initial;

  @override
  State<_DiscountEditor> createState() => _DiscountEditorState();
}

class _DiscountEditorState extends State<_DiscountEditor> {
  late final DiscountModel? _initial = widget.initial;
  late final _codeCtrl = TextEditingController(text: _initial?.code);
  late final _valueCtrl = TextEditingController(
      text: _initial == null ? '' : _plain(_initial.value));
  late final _minCtrl = TextEditingController(
      text: (_initial?.minSubtotal ?? 0) > 0
          ? _plain(_initial!.minSubtotal)
          : '');
  late final _limitCtrl =
      TextEditingController(text: _initial?.usageLimit?.toString() ?? '');
  late DiscountKind _kind = _initial?.kind ?? DiscountKind.percentage;
  late DateTime _startsAt = _initial?.startsAt ?? _today();
  late DateTime? _endsAt = _initial?.endsAt;
  late bool _oncePerCustomer = _initial?.oncePerCustomer ?? false;
  late bool _isActive = _initial?.isActive ?? true;
  late final Set<String> _productIds = {...?_initial?.productIds};
  late bool _allProducts = _productIds.isEmpty;
  String? _error;
  bool _busy = false;

  bool get _isNew => _initial == null;

  @override
  void dispose() {
    for (final ctrl in [_codeCtrl, _valueCtrl, _minCtrl, _limitCtrl]) {
      ctrl.dispose();
    }
    super.dispose();
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  DiscountModel _draft() => DiscountModel(
        id: _initial?.id ?? '',
        storeId: _initial?.storeId ?? widget.controller.storeId ?? '',
        code: DiscountModel.normalizeCode(_codeCtrl.text),
        kind: _kind,
        value: double.tryParse(_valueCtrl.text.trim()) ?? 0,
        minSubtotal: double.tryParse(_minCtrl.text.trim()) ?? 0,
        productIds: _allProducts ? const [] : _productIds.toList(),
        startsAt: _startsAt,
        endsAt: _endsAt,
        usageLimit: _limitCtrl.text.trim().isEmpty
            ? null
            : int.tryParse(_limitCtrl.text.trim()) ?? 0,
        oncePerCustomer: _oncePerCustomer,
        isActive: _isActive,
        createdAt: _initial?.createdAt,
      );

  Future<void> _save() async {
    final draft = _draft();
    if (!_allProducts && _productIds.isEmpty) {
      setState(() => _error = 'Pick at least one product, or apply it to all.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.controller.save(draft);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    final error = await widget.controller.delete(_initial!);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _startsAt = picked);
  }

  Future<void> _pickEnd() async {
    final suggested = _endsAt ?? _startsAt.add(const Duration(days: 7));
    final picked = await showDatePicker(
      context: context,
      initialDate: suggested.isBefore(_startsAt) ? _startsAt : suggested,
      firstDate: _startsAt,
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    // Through the end of the picked day.
    if (picked != null) {
      setState(() => _endsAt =
          DateTime(picked.year, picked.month, picked.day, 23, 59, 59));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listings = widget.controller.listings;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_isNew ? 'New discount code' : 'Edit ${_initial!.code}',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _codeCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Code',
                helperText: 'What customers type at checkout, e.g. WELCOME10',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<DiscountKind>(
              segments: [
                for (final kind in DiscountKind.values)
                  ButtonSegment(value: kind, label: Text(kind.label)),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _valueCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _kind == DiscountKind.percentage
                    ? 'Percent off'
                    : 'Amount off',
                suffixText: _kind == DiscountKind.percentage ? '%' : 'USD',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _minCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Minimum order (optional)',
                helperText: 'Before shipping',
                suffixText: 'USD',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Applies to', style: theme.textTheme.titleSmall),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Every product in my store'),
              value: _allProducts,
              onChanged: (v) => setState(() => _allProducts = v),
            ),
            if (!_allProducts)
              listings.isEmpty
                  ? Text('You have no listings yet.',
                      style: theme.textTheme.bodySmall)
                  : Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final product in listings)
                          FilterChip(
                            label: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220),
                              child: Text(product.title,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            selected: _productIds.contains(product.id),
                            onSelected: (on) => setState(() => on
                                ? _productIds.add(product.id)
                                : _productIds.remove(product.id)),
                          ),
                      ],
                    ),
            const SizedBox(height: AppSpacing.md),
            Text('Dates', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickStart,
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text('Starts ${Formatters.date(_startsAt)}'),
                ),
                OutlinedButton.icon(
                  onPressed: _pickEnd,
                  icon: const Icon(Icons.event_busy_outlined, size: 18),
                  label: Text(_endsAt == null
                      ? 'No end date'
                      : 'Ends ${Formatters.date(_endsAt!)}'),
                ),
                if (_endsAt != null)
                  TextButton(
                    onPressed: () => setState(() => _endsAt = null),
                    child: const Text('Clear end date'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _limitCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Total uses (optional)',
                helperText: 'Leave empty for no limit',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Once per customer'),
              value: _oncePerCustomer,
              onChanged: (v) => setState(() => _oncePerCustomer = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: const Text('Customers can use it within its dates'),
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                if (!_isNew)
                  TextButton(
                    onPressed: _busy ? null : _delete,
                    style:
                        TextButton.styleFrom(foregroundColor: AppColors.danger),
                    child: const Text('Delete'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_isNew ? 'Create code' : 'Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
