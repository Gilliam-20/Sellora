import 'product_model.dart';

class CartItemModel {
  CartItemModel({required this.product, this.quantity = 1, this.selectedVariant});

  final ProductModel product;
  int quantity;
  String? selectedVariant;

  double get lineTotal => product.sellPrice * quantity;
}
