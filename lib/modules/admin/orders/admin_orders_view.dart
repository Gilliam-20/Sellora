import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/responsive.dart';
import '../../../data/models/order_model.dart';
import '../../../data/models/order_refund_model.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/manifest_stub.dart';
import 'admin_orders_controller.dart';

class AdminOrdersView extends GetView<AdminOrdersController> {
  const AdminOrdersView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('All orders')),
      body: ResponsiveCenter(
        maxWidth: 900,
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: Obx(
                () => ListView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(
                      horizontal: context.pageHorizontalPadding,
                      vertical: AppSpacing.sm),
                  children: [
                    _FilterChip(
                        label: 'All',
                        selected: controller.statusFilter.value == null,
                        onTap: () => controller.setFilter(null)),
                    const SizedBox(width: AppSpacing.sm),
                    ...OrderStatus.values.map(
                      (status) => Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: _FilterChip(
                          label: status.label,
                          selected: controller.statusFilter.value == status,
                          onTap: () => controller.setFilter(status),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Obx(() {
                if (controller.isLoading.value) return const SelloraLoader();
                final orders = controller.filtered;
                if (orders.isEmpty) {
                  return const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No orders',
                      message: 'Nothing matches this filter yet.');
                }
                return RefreshIndicator(
                  onRefresh: controller.load,
                  child: ListView.separated(
                    padding: EdgeInsets.symmetric(
                        horizontal: context.pageHorizontalPadding,
                        vertical: AppSpacing.md),
                    itemCount: orders.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      return ManifestStub(
                        code: order.code,
                        title: Formatters.currency(order.total,
                            code: order.currency),
                        subtitle:
                            '${order.paymentStatus.label} · Seller: ${order.sellerId} · Buyer: ${order.buyerId}',
                        accentColor: AppColors.statusColor(order.status.name),
                        trailing: StatusBadge(
                          label: order.status.label,
                          color: AppColors.statusColor(order.status.name),
                        ),
                        onTap: () => _showRefund(context, order),
                      );
                    },
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

void _showRefund(BuildContext context, OrderModel order) {
  Get.find<AdminOrdersController>().openRefund(order);
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _RefundSheet(order: order),
  );
}

/// An order's payment and refund state, and the refund form. Refunds go
/// through `/refundOrder` (admin-only); the amounts here are what IntaSend
/// actually charged, in KES, which can differ from the order's display
/// total.
class _RefundSheet extends StatefulWidget {
  const _RefundSheet({required this.order});
  final OrderModel order;

  @override
  State<_RefundSheet> createState() => _RefundSheetState();
}

class _RefundSheetState extends State<_RefundSheet> {
  final _controller = Get.find<AdminOrdersController>();
  final _amount = TextEditingController();
  final _comment = TextEditingController();
  String _reason = refundReasons.first;
  String? _amountError;

  @override
  void dispose() {
    _amount.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit(OrderRefundInfo info) async {
    final error = _controller.validateAmount(_amount.text);
    setState(() => _amountError = error);
    if (error != null) return;
    final amount = _amount.text.trim().isEmpty
        ? info.remaining
        : double.parse(_amount.text.trim());
    final full = (amount - info.remaining).abs() <= 0.01;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Refund this order?'),
        content: Text(
            '${Formatters.currency(amount, code: info.currency)} goes back to '
            'the customer through IntaSend. This cannot be undone.'
            '${full && !info.shippedByCj ? '\n\nThe order will be cancelled, since CJ never received it.' : ''}'
            '${info.shippedByCj ? '\n\nCJ is already shipping this order, so it stays open.' : ''}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Refund')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final done = await _controller.refund(widget.order,
        amountText: _amount.text, reason: _reason, comment: _comment.text);
    if (done && mounted) {
      Navigator.of(context).pop();
      Get.snackbar('Refund sent',
          '${Formatters.currency(amount, code: info.currency)} refunded on ${widget.order.code}.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg,
          AppSpacing.xl + MediaQuery.of(context).viewInsets.bottom),
      child: Obx(() {
        if (_controller.isLoadingRefund.value) {
          return const SizedBox(height: 160, child: SelloraLoader());
        }
        final info = _controller.refundInfo.value;
        final error = _controller.refundError.value;
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.order.code, style: textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                  '${Formatters.currency(widget.order.total, code: widget.order.currency)} · ${widget.order.status.label}',
                  style: textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.md),
              if (info != null) ...[
                _row('Payment', widget.order.paymentStatus.label),
                _row('Provider', info.paymentProvider ?? '—'),
                _row(
                    'Charged',
                    info.chargedAmount == null
                        ? '—'
                        : Formatters.currency(info.chargedAmount!,
                            code: info.currency)),
                _row('Refunded',
                    Formatters.currency(info.refundedAmount, code: info.currency)),
                _row('Left to refund',
                    Formatters.currency(info.remaining, code: info.currency)),
                _row('CJ fulfilment', info.cjOrderStatus),
                if (info.refundStatus == 'FAILED' && info.refundError != null)
                  _notice('Last refund attempt failed: ${info.refundError}',
                      AppColors.danger),
                if (info.refunds.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text('Refund history', style: textTheme.titleSmall),
                  ...info.refunds.map((r) => _row(
                      r.createdAt == null
                          ? '—'
                          : Formatters.dateTime(r.createdAt!),
                      '${Formatters.currency(r.amount, code: r.currency)}'
                      '${r.reason == null ? '' : ' · ${r.reason}'}')),
                ],
                const SizedBox(height: AppSpacing.md),
                if (info.refusal != null)
                  _notice(info.refusal!, AppColors.slate)
                else
                  ..._form(info),
              ],
              if (error != null) _notice(error, AppColors.danger),
            ],
          ),
        );
      }),
    );
  }

  List<Widget> _form(OrderRefundInfo info) => [
        Text('Issue a refund', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Amount (${info.currency})',
            helperText:
                'Leave empty to refund the full ${Formatters.currency(info.remaining, code: info.currency)}',
            errorText: _amountError,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          value: _reason,
          decoration: const InputDecoration(labelText: 'Reason'),
          items: refundReasons
              .map((r) => DropdownMenuItem(value: r, child: Text(r)))
              .toList(),
          onChanged: (r) => setState(() => _reason = r ?? _reason),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _comment,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: Obx(() => FilledButton(
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: _controller.isRefunding.value
                    ? null
                    : () => _submit(info),
                child: Text(_controller.isRefunding.value
                    ? 'Refunding…'
                    : 'Refund'),
              )),
        ),
      ];

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 130,
                child: Text(label,
                    style: const TextStyle(color: AppColors.slate))),
            Expanded(child: Text(value)),
          ],
        ),
      );

  Widget _notice(String text, Color color) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Text(text, style: TextStyle(color: color)),
      );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppColors.cargoNavy,
      labelStyle: TextStyle(
          color: selected ? AppColors.cloud : AppColors.ink,
          fontWeight: FontWeight.w600),
      onSelected: (_) => onTap(),
    );
  }
}
