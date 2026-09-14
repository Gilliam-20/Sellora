import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/order_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/cart_repository.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../data/services/intasend_service.dart';

class CheckoutController extends GetxController {
  final CartRepository cartRepo = Get.find<CartRepository>();
  final OrderRepository _orderRepo = Get.find<OrderRepository>();
  final AuthRepository _authRepo = Get.find<AuthRepository>();

  final isPlacingOrder = false.obs;
  final errorMessage = RxnString();

  Future<void> placeOrder(
      {required String address, required String mpesaPhone}) async {
    final user = _authRepo.cachedUser;
    if (user == null || cartRepo.items.isEmpty) return;

    isPlacingOrder.value = true;
    errorMessage.value = null;
    try {
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
          total: cartRepo.subtotal,
          currency: 'KES',
          shippingAddress: address,
          paymentMethod: 'IntaSend M-Pesa',
          paymentReference:
              'MOCK-PAY-${DateTime.now().millisecondsSinceEpoch}',
          paymentStatus: OrderPaymentStatus.paid,
          createdAt: DateTime.now(),
        );
        await _orderRepo.placeOrder(order);
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
      // true) and would still fail if it ran. The real CJ variant id gap is
      // now closed (ProductVariant carries CJ's own `vid`, threaded through
      // here), but placeOrder still builds `shippingAddress` as a plain
      // string when createOrder requires `{countryCode, ...}`, and its
      // response parsing still assumes fields (`orderId`/`code`/
      // `serviceFeeAmount`) the adopted single-vendor backend doesn't return
      // (see ApiEndpoints.createOrder's doc comment). The payOrderMpesa call
      // below is correct against the real backend; what it's called with
      // isn't, yet.
      final draft = OrderModel(
        id: '',
        code: '',
        buyerId: user.uid,
        sellerId: sellerId,
        storeId: cartRepo.storeId,
        items: items,
        status: OrderStatus.pending,
        total: cartRepo.subtotal,
        currency: 'KES',
        shippingAddress: address,
        paymentMethod: 'IntaSend M-Pesa',
        createdAt: DateTime.now(),
      );
      final order = await _orderRepo.placeOrder(draft);

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
    Get.offAllNamed(Routes.buyerShell, arguments: {'tab': 2});
    Get.snackbar('Order placed', message);
  }
}
