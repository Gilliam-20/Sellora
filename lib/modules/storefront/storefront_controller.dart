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

  Future<void> load() async {
    isLoading.value = true;
    final slug = Get.parameters['slug'];
    if (slug == null || slug.isEmpty) {
      scope.clear();
      isLoading.value = false;
      return;
    }

    final store = await scope.resolveSlug(slug);
    if (store != null) {
      items.value = await _products.storeProducts(
        store.id,
        keyword: searchQuery.value,
        category: selectedCategory.value,
      );
    } else {
      items.clear();
    }
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
