import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../../data/models/product_model.dart';
import '../../../data/repositories/cart_repository.dart';
import '../../../data/repositories/product_repository.dart';
import '../../storefront/shell/storefront_links.dart';
import '../../storefront/storefront_session.dart';

/// A product page, `/s/{slug}/products/{productId}`. Opened from a product
/// card it starts from the card's product; opened from a link (or after a
/// refresh) it loads the listing by id, so product links can be shared.
class ProductDetailsController extends GetxController {
  ProductDetailsController({
    String? slug,
    String? productId,
    ProductModel? initial,
    StorefrontSession? session,
    ProductRepository? products,
    CartRepository? cart,
  })  : slug = slug ?? Get.parameters['slug'] ?? '',
        productId = productId ?? Get.parameters['productId'] ?? '',
        _initial = initial ??
            (Get.arguments is ProductModel
                ? Get.arguments as ProductModel
                : null),
        session = session ?? Get.find<StorefrontSession>(),
        _products = products ?? Get.find<ProductRepository>(),
        _cart = cart ?? Get.find<CartRepository>();

  final String slug;
  final String productId;
  final ProductModel? _initial;
  final StorefrontSession session;
  final ProductRepository _products;
  final CartRepository _cart;

  final product = Rxn<ProductModel>();
  final isLoading = true.obs;
  final notFound = false.obs;
  final quantity = 1.obs;
  final selectedVariant = Rxn<ProductVariant>();
  final previewImage = ''.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    final initial = _initial;
    if (initial != null && initial.id == productId) {
      _show(initial);
      return;
    }
    isLoading.value = true;
    notFound.value = false;
    await session.ensure(slug);
    final store = session.store;
    if (store == null) {
      isLoading.value = false;
      return;
    }
    try {
      final found = await _products.featuredProducts(store.id,
          ids: [productId], limit: 1);
      if (found.isEmpty) {
        notFound.value = true;
      } else {
        _show(found.first);
      }
    } catch (e) {
      debugPrint('ProductDetailsController.load: $e');
      notFound.value = true;
    } finally {
      isLoading.value = false;
    }
  }

  void _show(ProductModel p) {
    product.value = p;
    previewImage.value = p.imageUrl;
    if (p.visibleVariants.isNotEmpty) selectVariant(p.visibleVariants.first);
    isLoading.value = false;
  }

  /// The main photo first, then the rest, without repeats.
  List<String> get gallery {
    final p = product.value;
    if (p == null) return const [];
    return {
      if (p.imageUrl.isNotEmpty) p.imageUrl,
      ...p.images.where((i) => i.isNotEmpty),
    }.toList();
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
    final p = product.value;
    if (p == null) return;
    _cart.add(p, variant: selectedVariant.value, quantity: quantity.value);
  }

  /// Adds it and goes straight to the cart.
  void buyNow() {
    addToCart();
    Get.toNamed(session.path(StorefrontPaths.cart));
  }
}
