import 'package:get/get.dart';
import 'cart/cart_controller.dart';
import 'checkout/checkout_controller.dart';
import 'orders/buyer_orders_controller.dart';
import 'orders/order_page.dart';
import 'product_details/product_details_controller.dart';

// One binding per storefront page (TODO §20). The store itself comes from
// StorefrontSession, which every page's StorefrontFrame loads.

class CartBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<CartController>(() => CartController());
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

class BuyerOrdersBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<BuyerOrdersController>(() => BuyerOrdersController());
  }
}

class OrderPageBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<OrderPageController>(() => OrderPageController());
  }
}
