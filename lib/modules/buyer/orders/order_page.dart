import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_metrics.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_page.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../data/models/order_model.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../data/services/currency_service.dart';
import '../../storefront/design/storefront_theme.dart';
import '../../storefront/shell/storefront_links.dart';
import '../../storefront/shell/storefront_page.dart';
import '../../storefront/storefront_session.dart';

/// `/s/{slug}/orders/{orderId}`: one of the buyer's orders. Straight after
/// checkout it's the order confirmation ("Thank you"), which is also where
/// the card payment page sends them back to; later it's the order's
/// status, items, totals, delivery address and tracking.
class OrderPageController extends GetxController {
  OrderPageController({
    String? slug,
    String? orderId,
    Object? arguments,
    StorefrontSession? session,
    OrderRepository? orders,
  })  : slug = slug ?? Get.parameters['slug'] ?? '',
        orderId = orderId ?? Get.parameters['orderId'] ?? '',
        session = session ?? Get.find<StorefrontSession>(),
        _orders = orders ?? Get.find<OrderRepository>() {
    final args = arguments ?? Get.arguments;
    if (args is Map && args['placed'] is OrderModel) {
      justPlaced = true;
      message = args['message'] as String?;
      final placed = args['placed'] as OrderModel;
      if (placed.id == this.orderId) order.value = placed;
    }
  }

  final String slug;
  final String orderId;
  final StorefrontSession session;
  final OrderRepository _orders;

  /// Arrived from checkout, rather than from the order history.
  bool justPlaced = false;

  /// What checkout said about payment ("complete the M-Pesa prompt…").
  String? message;

  final order = Rxn<OrderModel>();
  final isLoading = true.obs;
  final notFound = false.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = order.value == null;
    await session.ensure(slug);
    if (session.customer == null) {
      isLoading.value = false;
      return;
    }
    try {
      final fresh = await _orders.buyerOrder(orderId);
      if (fresh == null || fresh.storeId != session.store?.id) {
        if (order.value == null) notFound.value = true;
      } else {
        order.value = fresh;
      }
    } catch (_) {
      if (order.value == null) notFound.value = true;
    } finally {
      isLoading.value = false;
    }
  }
}

class OrderPage extends GetView<OrderPageController> {
  const OrderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    return StorefrontPage(
      title: 'Order',
      onRefresh: controller.load,
      slivers: (context, store, design) => [
        SliverToBoxAdapter(
          child: StorefrontContent(
            maxWidth: 760,
            child: Obx(() {
              final order = controller.order.value;
              if (session.customer == null) {
                final here =
                    session.path(StorefrontPaths.order(controller.orderId));
                return EmptyState(
                  icon: Icons.lock_outline,
                  title: 'Sign in to see this order',
                  message: 'Orders are only shown to the customer who '
                      'placed them.',
                  actionLabel: 'Sign in',
                  onAction: () => Get.toNamed(
                      session.path(StorefrontPaths.loginThen(here))),
                );
              }
              if (order == null) {
                if (controller.isLoading.value) {
                  return const SizedBox(height: 240, child: AppLoadingState());
                }
                return EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'Order not found',
                  message: 'It may belong to another account.',
                  actionLabel: 'Your orders',
                  onAction: () =>
                      Get.offNamed(session.path(StorefrontPaths.orders)),
                );
              }
              return _OrderDetail(
                order: order,
                justPlaced: controller.justPlaced,
                message: controller.message,
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _OrderDetail extends StatelessWidget {
  const _OrderDetail(
      {required this.order, required this.justPlaced, this.message});
  final OrderModel order;
  final bool justPlaced;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final style = StoreStyle.of(context);
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final session = Get.find<StorefrontSession>();
    final currency = Get.find<CurrencyService>();
    String money(double v) => currency.format(v, fromCode: order.currency);
    final paid = order.paymentStatus == OrderPaymentStatus.paid;

    Widget row(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(child: Text(label, style: textTheme.bodyMedium)),
              Text(value,
                  style: bold
                      ? AppTypography.price(size: 16, color: style.onSurface)
                      : textTheme.bodyMedium),
            ],
          ),
        );

    Widget panel(String title, List<Widget> children) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: AppSpacing.md),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: style.panel(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              ...children,
            ],
          ),
        );

    final tracking = order.tracking;
    final trackingNumber = tracking?.trackingNumber ?? order.trackingNumber;
    final trackingUrl = tracking?.trackingUrl;

    return Obx(() => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (justPlaced) ...[
              Icon(Icons.check_circle_outline, size: 48, color: scheme.primary),
              const SizedBox(height: AppSpacing.sm),
              Text(style.heading('Thank you for your order'),
                  style: style.headingStyle(textTheme.headlineSmall)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                  paid
                      ? 'Your payment has been received. We\'ll let you know '
                          'when it ships.'
                      : message ??
                          'Finish paying to confirm it. This page updates '
                              'once payment is received.',
                  style: textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.md),
            ] else
              Text(style.heading('Order ${order.code}'),
                  style: style.headingStyle(textTheme.headlineSmall)),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (justPlaced) Text(order.code, style: textTheme.titleSmall),
                Text('Placed ${Formatters.date(order.createdAt)}',
                    style: textTheme.bodySmall),
                Chip(label: Text(order.status.label)),
                Chip(label: Text('Payment: ${order.paymentStatus.label}')),
              ],
            ),
            panel('Items', [
              for (final item in order.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${item.quantity} × ${item.title}',
                                style: textTheme.bodyMedium),
                            if (item.variantLabel case final v?)
                              Text(v, style: textTheme.bodySmall),
                          ],
                        ),
                      ),
                      Text(money(item.total), style: textTheme.bodyMedium),
                    ],
                  ),
                ),
              const Divider(),
              row('Subtotal', money(order.itemsSubtotal)),
              if (order.discountAmount > 0)
                row('Discount${order.discountCode == null ? '' : ' (${order.discountCode})'}',
                    '−${money(order.discountAmount)}'),
              row('Shipping${order.logisticName == null ? '' : ' · ${order.logisticName}'}',
                  money(order.shippingFee)),
              row('Total', money(order.total), bold: true),
              if (currency.code.value != order.currency)
                Text('Charged in ${order.currency}.',
                    style: textTheme.bodySmall),
            ]),
            panel('Delivery', [
              Text(order.shippingAddress.fullName, style: textTheme.bodyMedium),
              Text(order.shippingAddress.summary, style: textTheme.bodySmall),
              Text(order.shippingAddress.phone, style: textTheme.bodySmall),
              if (trackingNumber != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                    'Tracking: $trackingNumber'
                    '${tracking?.carrier == null ? '' : ' (${tracking!.carrier})'}',
                    style: textTheme.bodyMedium),
                if (tracking?.statusLabel case final label?)
                  Text(label, style: textTheme.bodySmall),
                if (trackingUrl != null && trackingUrl.startsWith('http'))
                  TextButton(
                    onPressed: () => launchUrl(Uri.parse(trackingUrl),
                        mode: LaunchMode.externalApplication),
                    child: const Text('Track your parcel'),
                  ),
              ] else
                Text('You\'ll get a tracking number here once it ships.',
                    style: textTheme.bodySmall),
            ]),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                ElevatedButton(
                  onPressed: () =>
                      Get.offAllNamed(session.path(StorefrontPaths.shop)),
                  child: const Text('Continue shopping'),
                ),
                OutlinedButton(
                  onPressed: () =>
                      Get.toNamed(session.path(StorefrontPaths.orders)),
                  child: const Text('All your orders'),
                ),
              ],
            ),
          ],
        ));
  }
}
