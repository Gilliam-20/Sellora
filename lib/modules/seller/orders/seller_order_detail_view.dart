import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/common.dart';
import '../../../data/models/fee_settings.dart';
import '../../../data/models/order_model.dart';
import '../../../data/models/order_timeline.dart';
import 'order_filters.dart';
import 'seller_order_detail_controller.dart';
import 'seller_orders_view.dart' show paymentColor;

class SellerOrderDetailView extends GetView<SellerOrderDetailController> {
  const SellerOrderDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(controller.order.value?.code ?? 'Order')),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: controller.refreshOrder,
          ),
        ],
      ),
      body: Obx(() {
        final order = controller.order.value;
        if (order == null) {
          return const Center(child: Text('This order isn\'t available.'));
        }
        final main = [
          _ItemsCard(order: order),
          _PaymentCard(order: order),
          _TimelineCard(controller: controller, currency: order.currency),
        ];
        final side = [
          _ActionsCard(controller: controller, order: order),
          _CustomerCard(order: order),
          _ShippingCard(order: order),
        ];
        return RefreshIndicator(
          onRefresh: controller.refreshOrder,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ResponsiveCenter(
              maxWidth: 1080,
              padding: EdgeInsets.symmetric(
                  horizontal: context.pageHorizontalPadding,
                  vertical: AppSpacing.md),
              child: LayoutBuilder(builder: (context, constraints) {
                if (constraints.maxWidth < 760) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _spaced([side.first, ...main, ...side.skip(1)]),
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _spaced(main)),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      flex: 2,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _spaced(side)),
                    ),
                  ],
                );
              }),
            ),
          ),
        );
      }),
    );
  }

  static List<Widget> _spaced(List<Widget> cards) => [
        for (final (i, card) in cards.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          card,
        ],
      ];
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children, this.trailing});
  final String title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
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
              Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleSmall)),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value,
      {this.emphasis = false, this.muted = false});
  final String label;
  final String value;
  final bool emphasis;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium;
    final style = emphasis
        ? base?.copyWith(fontWeight: FontWeight.w700)
        : muted
            ? base?.copyWith(color: AppColors.slate)
            : base;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
              child: Text(value, style: style, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  const _ActionsCard({required this.controller, required this.order});
  final SellerOrderDetailController controller;
  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final next = controller.nextStatus;
    return _Card(
      title: 'Status',
      children: [
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            StatusBadge(
                label: 'Payment: ${order.paymentStatus.label}',
                color: paymentColor(order.paymentStatus)),
            StatusBadge(
                label: order.fulfillmentLabel,
                color: AppColors.statusColor(order.status.name)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
            'Placed ${Formatters.dateTime(order.createdAt)} · ${order.channelLabel}',
            style: Theme.of(context).textTheme.bodySmall),
        if (next != null || controller.canCancel) ...[
          const SizedBox(height: AppSpacing.md),
          Obx(() {
            final busy = controller.isBusy.value;
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (next != null)
                  ElevatedButton(
                    onPressed: busy ? null : controller.advanceStatus,
                    child: Text(next == OrderStatus.shipped
                        ? 'Mark shipped'
                        : 'Mark delivered'),
                  ),
                if (controller.canCancel)
                  OutlinedButton(
                    onPressed: busy ? null : () => _confirmCancel(context),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger),
                    child: const Text('Cancel order'),
                  ),
              ],
            );
          }),
        ],
        if (order.status == OrderStatus.pending &&
            order.paymentStatus == OrderPaymentStatus.pending) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Waiting for the customer to pay. Unpaid orders are cancelled '
            'automatically after an hour.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (order.paymentStatus == OrderPaymentStatus.paid &&
            order.status != OrderStatus.delivered) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'A paid order can\'t be cancelled here: cancelling it means '
            'refunding the customer, which Sellora support does.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: const Text(
            'The customer hasn\'t paid, so nothing is refunded. They can\'t '
            'pay for it after this.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep it')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.cancelOrder();
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.order});
  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return _Card(
      title: 'Products (${order.itemCount})',
      children: [
        for (final item in order.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.stub),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: item.imageUrl.isEmpty
                        ? Container(color: AppColors.mist)
                        : CachedNetworkImage(
                            imageUrl: item.imageUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                Container(color: AppColors.mist)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium),
                      Text(
                        [
                          if (item.variantLabel != null &&
                              item.variantLabel!.isNotEmpty)
                            item.variantLabel!,
                          if (item.variantId != null)
                            'CJ variant ${item.variantId}',
                        ].join(' · '),
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${item.quantity} × ${Formatters.currency(item.unitPrice, code: order.currency)}',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.order});
  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    String money(double amount) =>
        Formatters.currency(amount, code: order.currency);
    final rateLabel = FeeSettings.percentOf(order.serviceFeeRate);
    final feeBase = order.serviceFeeBase == 'subtotal_and_shipping'
        ? 'products and shipping'
        : 'products';
    return _Card(
      title: 'Payment',
      trailing: StatusBadge(
          label: order.paymentStatus.label,
          color: paymentColor(order.paymentStatus)),
      children: [
        _Line('Products', money(order.itemsSubtotal)),
        if (order.discountAmount > 0)
          _Line(
              'Discount${order.discountCode == null ? '' : ' (${order.discountCode})'}',
              '− ${money(order.discountAmount)}'),
        _Line(
            'Shipping${order.logisticName == null ? '' : ' (${order.logisticName})'}',
            money(order.shippingFee)),
        _Line('Customer paid', money(order.total), emphasis: true),
        if (order.refundedAmount > 0)
          _Line('Refunded to customer', '− ${money(order.refundedAmount)}'),
        const Divider(height: AppSpacing.lg),
        _Line('Sellora service fee ($rateLabel% of $feeBase)',
            '− ${money(order.serviceFeeAmount)}',
            muted: true),
        _Line('Your earnings', money(order.sellerRevenue), emphasis: true),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Your earnings are the product price less CJ\'s cost and the fee. '
          'The fee rate is fixed when the order is placed. '
          'Paid with ${order.paymentMethod}'
          '${order.paymentReference == null ? '' : ' (ref ${order.paymentReference})'}.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.order});
  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final address = order.shippingAddress;
    final textTheme = Theme.of(context).textTheme;
    return _Card(
      title: 'Customer',
      children: [
        Text(order.customerName, style: textTheme.bodyLarge),
        if (address.email != null && address.email!.isNotEmpty)
          SelectableText(address.email!, style: textTheme.bodyMedium),
        if (address.phone.isNotEmpty)
          SelectableText(address.phone, style: textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.sm),
        Text('Ships to', style: textTheme.labelMedium),
        SelectableText(
            address.summary.isEmpty ? 'No address on file' : address.summary,
            style: textTheme.bodyMedium),
      ],
    );
  }
}

class _ShippingCard extends StatelessWidget {
  const _ShippingCard({required this.order});
  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final tracking = order.tracking;
    final number = tracking?.trackingNumber ?? order.trackingNumber;
    final textTheme = Theme.of(context).textTheme;
    return _Card(
      title: 'Fulfilment',
      children: [
        _Line('CJ Dropshipping', order.cjStatusLabel),
        _Line('Shipping method', order.logisticName ?? 'Cheapest available'),
        if (tracking != null) _Line('Shipment', tracking.statusLabel),
        if (tracking?.carrier != null) _Line('Carrier', tracking!.carrier!),
        if (number != null && number.isNotEmpty) ...[
          _Line('Tracking number', number),
          if (tracking?.trackingUrl != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => launchUrl(Uri.parse(tracking!.trackingUrl!),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Track parcel'),
              ),
            ),
        ],
        if (tracking != null && tracking.events.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text('Carrier scans', style: textTheme.labelMedium),
          for (final event in tracking.events.take(5))
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                [
                  if (event.at != null) event.at!,
                  event.description,
                  if (event.location != null) event.location!,
                ].join(' · '),
                style: textTheme.bodySmall,
              ),
            ),
        ],
      ],
    );
  }
}

class _TimelineCard extends StatefulWidget {
  const _TimelineCard({required this.controller, required this.currency});
  final SellerOrderDetailController controller;
  final String currency;

  @override
  State<_TimelineCard> createState() => _TimelineCardState();
}

class _TimelineCardState extends State<_TimelineCard> {
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (await widget.controller.addNote(_noteCtrl.text)) _noteCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final textTheme = Theme.of(context).textTheme;
    return _Card(
      title: 'Timeline',
      children: [
        TextField(
          controller: _noteCtrl,
          minLines: 1,
          maxLines: 4,
          maxLength: 2000,
          decoration: InputDecoration(
            hintText: 'Add a note (only you and Sellora see it)',
            counterText: '',
            suffixIcon: Obx(() => IconButton(
                  tooltip: 'Add note',
                  icon: controller.isSavingNote.value
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                  onPressed: controller.isSavingNote.value ? null : _save,
                )),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Obx(() {
          if (controller.isLoadingTimeline.value &&
              controller.timeline.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Center(child: SelloraLoader(size: 24)),
            );
          }
          if (controller.timelineError.value != null) {
            return Row(
              children: [
                Expanded(
                    child: Text(controller.timelineError.value!,
                        style: textTheme.bodySmall)),
                TextButton(
                    onPressed: controller.loadTimeline,
                    child: const Text('Retry')),
              ],
            );
          }
          final entries = controller.timeline
              .where((e) => e.describe(currency: widget.currency).isNotEmpty)
              .toList();
          if (entries.isEmpty) {
            return Text('Nothing has happened yet.',
                style: textTheme.bodySmall);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: entries
                .map((e) => _TimelineEntry(entry: e, currency: widget.currency))
                .toList(),
          );
        }),
      ],
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({required this.entry, required this.currency});
  final OrderTimelineEntry entry;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final lines = entry.describe(currency: currency);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(
              entry.isNote ? Icons.sticky_note_2_outlined : Icons.circle,
              size: entry.isNote ? 16 : 8,
              color:
                  entry.isNote ? AppColors.manifestGoldDeep : AppColors.slate,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.isNote)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.manifestGold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadii.stub),
                    ),
                    child: SelectableText(lines.join('\n'),
                        style: textTheme.bodyMedium),
                  )
                else
                  for (final line in lines)
                    Text(line, style: textTheme.bodyMedium),
                Text(
                  '${entry.actorLabel} · ${Formatters.dateTime(entry.at)}',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
