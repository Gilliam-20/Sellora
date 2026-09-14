import 'product_model.dart';

class CartItemModel {
  CartItemModel(
      {required this.product, this.quantity = 1, this.selectedVariant});

  final ProductModel product;
  int quantity;

  /// The real CJ SKU chosen for this line, if the product has variants —
  /// carries the `vid` checkout needs (see [ProductVariant]). Pricing still
  /// comes from [product.sellPrice], the seller's own listing price, not
  /// this variant's CJ price.
  ProductVariant? selectedVariant;

  double get lineTotal => product.sellPrice * quantity;
}
