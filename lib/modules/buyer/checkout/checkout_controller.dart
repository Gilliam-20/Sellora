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

  Future<void> placeOrder({required String address, required String mpesaPhone}) async {
    final user = _authRepo.cachedUser;
    if (user == null || cartRepo.items.isEmpty) return;

    isPlacingOrder.value = true;
    errorMessage.value = null;
    try {
      String? paymentReference;
      if (!AppConstants.useMockData) {
        final intasend = Get.find<IntasendService>();
        final result = await intasend.collectMpesa(
          phone: Formatters.toMpesaFormat(mpesaPhone),
          amountKes: cartRepo.subtotal,
          narrative: 'Sellora order',
        );
        paymentReference = result.reference;
      } else {
        await Future.delayed(const Duration(seconds: 2));
        paymentReference = 'MOCK-PAY-${DateTime.now().millisecondsSinceEpoch}';
      }

      // A real multi-seller cart would split into one order per seller.
      // Simplified here to a single order against the first item's seller.
      final sellerId = cartRepo.items.first.product.sellerId ?? 'unknown-seller';
      final order = OrderModel(
        id: 'order-${DateTime.now().millisecondsSinceEpoch}',
        code: 'SLR-${1000 + (DateTime.now().millisecondsSinceEpoch % 9000)}',
        buyerId: user.uid,
        sellerId: sellerId,
        items: cartRepo.items
            .map((i) => OrderItem(
                  productId: i.product.id,
                  title: i.product.title,
                  imageUrl: i.product.imageUrl,
                  quantity: i.quantity,
                  unitPrice: i.product.sellPrice,
                  variant: i.selectedVariant,
                ))
            .toList(),
        status: OrderStatus.pending,
        total: cartRepo.subtotal,
        currency: 'KES',
        shippingAddress: address,
        paymentMethod: 'IntaSend M-Pesa',
        paymentReference: paymentReference,
        createdAt: DateTime.now(),
      );

      await _orderRepo.placeOrder(order);
      cartRepo.clear();
      Get.offAllNamed(Routes.buyerShell, arguments: {'tab': 2});
      Get.snackbar('Order placed', 'Your order ${order.code} is on its way to processing.');
    } catch (e) {
      errorMessage.value = 'Payment didn\'t go through. Check the number and try again.';
    } finally {
      isPlacingOrder.value = false;
    }
  }
}
