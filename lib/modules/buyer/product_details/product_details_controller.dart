import 'package:get/get.dart';
import '../../../data/models/product_model.dart';
import '../../../data/repositories/cart_repository.dart';

class ProductDetailsController extends GetxController {
  final CartRepository _cartRepo = Get.find<CartRepository>();

  late final ProductModel product;
  final quantity = 1.obs;
  final selectedVariant = Rxn<ProductVariant>();

  @override
  void onInit() {
    super.onInit();
    product = Get.arguments as ProductModel;
    if (product.variants.isNotEmpty) {
      selectedVariant.value = product.variants.first;
    }
  }

  void increment() => quantity.value++;
  void decrement() {
    if (quantity.value > 1) quantity.value--;
  }

  void addToCart() {
    _cartRepo.add(product,
        variant: selectedVariant.value, quantity: quantity.value);
    Get.snackbar('Added to cart', '${product.title} · qty ${quantity.value}');
  }
}
