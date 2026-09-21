import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/order_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/cart_repository.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/services/intasend_service.dart';

class CheckoutController extends GetxController {
  final CartRepository cartRepo = Get.find<CartRepository>();
  final OrderRepository _orderRepo = Get.find<OrderRepository>();
  final AuthRepository _authRepo = Get.find<AuthRepository>();
  final NotificationRepository _notificationRepo =
      Get.find<NotificationRepository>();
  final ProductRepository _productRepo = Get.find<ProductRepository>();

  final isPlacingOrder = false.obs;
  final errorMessage = RxnString();

  /// Shipping estimate for the whole cart to the currently selected
  /// destination — the sum of a per-line [ProductRepository.estimateShipping]
  /// call, same freight source the seller's landed-cost card already uses.
  /// Display-only: the mock-mode order below charges it as quoted, and the
  /// real-mode order re-prices freight server-side from `createOrder`
  /// regardless of what this shows (see functions/lib/orders.js).
  final shippingFee = 0.0.obs;
  final isEstimatingShipping = false.obs;

  double get total => cartRepo.subtotal + shippingFee.value;

  /// Re-quotes [shippingFee] for [countryCode]. Called on load and whenever
  /// the buyer changes the destination country — never blocks or fails
  /// checkout itself, since it's only a display breakdown.
  Future<void> refreshShippingEstimate(String countryCode) async {
    if (cartRepo.items.isEmpty) {
      shippingFee.value = 0;
      return;
    }
    isEstimatingShipping.value = true;
    try {
      final estimates = await Future.wait(cartRepo.items.map((item) {
        final vid = item.selectedVariant?.vid ??
            (item.product.variants.isNotEmpty
                ? item.product.variants.first.vid
                : item.product.cjProductId);
        return _productRepo.estimateShipping(
          vid: vid,
          quantity: item.quantity,
          endCountryCode: countryCode,
        );
      }));
      shippingFee.value =
          estimates.fold(0.0, (sum, estimate) => sum + estimate.cost);
    } catch (_) {
      shippingFee.value = 0;
    } finally {
      isEstimatingShipping.value = false;
    }
  }

  Future<void> placeOrder(
      {required String address,
      required String countryCode,
      required String mpesaPhone}) async {
    final user = _authRepo.cachedUser;
    if (user == null || cartRepo.items.isEmpty) return;

    isPlacingOrder.value = true;
    errorMessage.value = null;
    try {
      final shippingAddress =
          ShippingAddress(countryCode: countryCode, line: address);
      // A real multi-seller cart would split into one order per seller.
      // Simplified here to a single order against the first item's
      // seller — matches functions/src/orders.ts's createOrder, which
      // rejects a cart mixing sellers rather than silently misattributing
      // it.
      final sellerId =
          cartRepo.items.first.product.sellerId ?? 'unknown-seller';
      final items = cartRepo.items
          .map((i) => OrderItem(
                productId: i.product.id,
                cjProductId: i.product.cjProductId,
                title: i.product.title,
                imageUrl: i.product.imageUrl,
                quantity: i.quantity,
                unitPrice: i.product.sellPrice,
                variantId: i.selectedVariant?.vid,
                variantLabel: i.selectedVariant?.label,
              ))
          .toList();

      if (AppConstants.useMockData) {
        // Demo mode fakes an instant successful payment — there's no
        // server to re-price against and no webhook to confirm it later,
        // so the order is written already "paid" for a smooth demo.
        await Future.delayed(const Duration(seconds: 2));
        final order = OrderModel(
          id: 'order-${DateTime.now().millisecondsSinceEpoch}',
          code: 'SLR-${1000 + (DateTime.now().millisecondsSinceEpoch % 9000)}',
          buyerId: user.uid,
          sellerId: sellerId,
          storeId: cartRepo.storeId,
          items: items,
          status: OrderStatus.pending,
          total: total,
          currency: cartRepo.currency,
          shippingAddress: shippingAddress,
          paymentMethod: 'IntaSend M-Pesa',
          paymentReference: 'MOCK-PAY-${DateTime.now().millisecondsSinceEpoch}',
          paymentStatus: OrderPaymentStatus.paid,
          createdAt: DateTime.now(),
          shippingFee: shippingFee.value,
        );
        await _orderRepo.placeOrder(order);
        await _notificationRepo.notifyOrderPlaced(order);
        _onOrderPlaced(order.code,
            'Your order ${order.code} is on its way to processing.');
        return;
      }

      // Real mode: create the order server-side — re-priced from
      // listings, ignoring whatever total this draft carries — *before*
      // contacting IntaSend, so the server-assigned order id can be the
      // payment's orderId. See FirebaseOrderRepository.placeOrder and
      // functions/index.js's intasendWebhook, which is what actually
      // confirms payment and starts CJ fulfillment; this controller does
      // neither itself anymore.
      //
      // NOTE: this whole branch is unreachable today (useMockData is always
      // true), but should now actually work against the real backend once
      // it is: the CJ variant id gap, the shippingAddress shape, and
      // placeOrder's response parsing are all closed (see
      // ApiEndpoints.createOrder's doc comment for what's still open —
      // shippingAddress.line stays one free-text string, not CJ's full
      // fulfillment-address shape).
      final draft = OrderModel(
        id: '',
        code: '',
        buyerId: user.uid,
        sellerId: sellerId,
        storeId: cartRepo.storeId,
        items: items,
        status: OrderStatus.pending,
        total: total,
        currency: cartRepo.currency,
        shippingAddress: shippingAddress,
        paymentMethod: 'IntaSend M-Pesa',
        createdAt: DateTime.now(),
        shippingFee: shippingFee.value,
      );
      final order = await _orderRepo.placeOrder(draft);
      await _notificationRepo.notifyOrderPlaced(order);

      final intasend = Get.find<IntasendService>();
      await intasend.payOrderMpesa(
        orderId: order.id,
        phoneNumber: Formatters.toMpesaFormat(mpesaPhone),
      );
      _onOrderPlaced(order.code,
          'Order ${order.code} placed — complete the M-Pesa prompt on your phone to finish payment.');
    } catch (e) {
      errorMessage.value =
          'Payment didn\'t go through. Check the number and try again.';
    } finally {
      isPlacingOrder.value = false;
    }
  }

  void _onOrderPlaced(String code, String message) {
    cartRepo.clear();
    final slug = Get.parameters['slug'];
    Get.offAllNamed(
      slug != null && slug.isNotEmpty ? '/s/$slug' : Routes.marketing,
      arguments: {'tab': 2},
    );
    Get.snackbar('Order placed', message);
  }
}
