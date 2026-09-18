import 'package:get/get.dart';
import '../../../data/models/product_model.dart';
import '../../../data/repositories/cart_repository.dart';

class ProductDetailsController extends GetxController {
  final CartRepository _cartRepo = Get.find<CartRepository>();

  late final ProductModel product;
  final quantity = 1.obs;
  final selectedVariant = Rxn<ProductVariant>();
  final previewImage = ''.obs;

  @override
  void onInit() {
    super.onInit();
    product = Get.arguments as ProductModel;
    previewImage.value = product.imageUrl;
    if (product.visibleVariants.isNotEmpty) {
      selectVariant(product.visibleVariants.first);
    }
  }

  /// Swaps the preview image when the chosen SKU has its own photo. No price
  /// recalculation: the buyer always pays [ProductModel.sellPrice] regardless
  /// of variant (see [ProductVariant]'s own doc comment) — this is purely
  /// about picking which physical SKU ships.
  void selectVariant(ProductVariant variant) {
    selectedVariant.value = variant;
    final image = variant.image;
    if (image != null && image.isNotEmpty) previewImage.value = image;
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
