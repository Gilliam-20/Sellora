import 'package:get/get.dart';

import '../../data/models/product_model.dart';
import '../../data/repositories/product_repository.dart';
import 'store_scope.dart';

class StorefrontController extends GetxController {
  final StoreScope scope = Get.find<StoreScope>();
  final ProductRepository _products = Get.find<ProductRepository>();

  final items = <ProductModel>[].obs;
  final isLoading = true.obs;
  final selectedCategory = 'All'.obs;
  final searchQuery = ''.obs;
  final categories = const ['All', 'Electronics', 'Fashion', 'Home'];

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// The store itself is resolved once by BuyerShellController (which gates
  /// this whole tab tree on that resolution finishing) — this just reads
  /// the already-resolved StoreScope.current, so filtering never re-triggers
  /// a redundant slug lookup.
  Future<void> load() async {
    final store = scope.current.value;
    if (store == null) {
      items.clear();
      isLoading.value = false;
      return;
    }
    isLoading.value = true;
    items.value = await _products.storeProducts(
      store.id,
      keyword: searchQuery.value,
      category: selectedCategory.value,
    );
    isLoading.value = false;
  }

  void search(String query) {
    searchQuery.value = query;
    load();
  }

  void selectCategory(String category) {
    selectedCategory.value = category;
    load();
  }
}
