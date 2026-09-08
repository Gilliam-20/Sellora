import 'package:get/get.dart';
import '../models/cart_item_model.dart';
import '../models/product_model.dart';

/// The cart is always in-memory/local until the buyer checks out — there
/// is no meaningful "mock vs production" split here, so this is the one
/// repository with a single implementation, registered as a permanent
/// singleton in InitialBinding.
class CartRepository extends GetxService {
  final RxList<CartItemModel> items = <CartItemModel>[].obs;

  /// The store (see StoreModel) this cart's items belong to. A buyer
  /// shops exactly one store, so switching stores — or a different buyer
  /// signing in on the same session — starts a fresh cart instead of
  /// mixing two sellers' items together.
  String? _storeId;
  String? get storeId => _storeId;

  void setStore(String? storeId) {
    if (_storeId != storeId) {
      _storeId = storeId;
      items.clear();
    }
  }

  double get subtotal => items.fold(0, (sum, item) => sum + item.lineTotal);
  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  void add(ProductModel product, {String? variant, int quantity = 1}) {
    final existingIndex = items.indexWhere(
        (i) => i.product.id == product.id && i.selectedVariant == variant);
    if (existingIndex != -1) {
      items[existingIndex].quantity += quantity;
      items.refresh();
    } else {
      items.add(CartItemModel(
          product: product, quantity: quantity, selectedVariant: variant));
    }
  }

  void updateQuantity(String productId, int quantity) {
    final index = items.indexWhere((i) => i.product.id == productId);
    if (index == -1) return;
    if (quantity <= 0) {
      items.removeAt(index);
    } else {
      items[index].quantity = quantity;
      items.refresh();
    }
  }

  void remove(String productId) {
    items.removeWhere((i) => i.product.id == productId);
  }

  void clear() => items.clear();
}
