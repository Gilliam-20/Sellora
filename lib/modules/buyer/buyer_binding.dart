import 'package:get/get.dart';
import 'cart/cart_controller.dart';
import 'checkout/checkout_controller.dart';
import 'home/buyer_home_controller.dart';
import 'orders/buyer_orders_controller.dart';
import 'product_details/product_details_controller.dart';
import 'shell/buyer_shell_controller.dart';

class BuyerBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<BuyerShellController>(() => BuyerShellController());
    Get.lazyPut<BuyerHomeController>(() => BuyerHomeController());
    Get.lazyPut<CartController>(() => CartController());
    Get.lazyPut<BuyerOrdersController>(() => BuyerOrdersController());
  }
}

class ProductDetailsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ProductDetailsController>(() => ProductDetailsController());
  }
}

class CheckoutBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<CheckoutController>(() => CheckoutController());
  }
}
