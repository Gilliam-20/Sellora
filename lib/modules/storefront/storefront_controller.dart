import 'package:get/get.dart';

import '../../data/models/product_model.dart';
import '../../data/repositories/product_repository.dart';
import 'store_scope.dart';

class StorefrontController extends GetxController {
  final StoreScope scope = Get.find<StoreScope>();
  final ProductRepository _products = Get.find<ProductRepository>();

  final items = <ProductModel>[].obs;
  final isLoading = true.obs;

  /// Whether the last page came back full, so another may exist.
  final hasMore = false.obs;
  final isLoadingMore = false.obs;
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
    final page = await _products.storeProducts(
      store.id,
      keyword: searchQuery.value,
      category: selectedCategory.value,
    );
    items.value = page;
    hasMore.value = page.length == storefrontPageSize;
    isLoading.value = false;
  }

  /// Appends the next page of the current search/category.
  Future<void> loadMore() async {
    final store = scope.current.value;
    if (store == null || !hasMore.value || isLoadingMore.value) return;
    isLoadingMore.value = true;
    try {
      final page = await _products.storeProducts(
        store.id,
        keyword: searchQuery.value,
        category: selectedCategory.value,
        offset: items.length,
      );
      items.addAll(page);
      hasMore.value = page.length == storefrontPageSize;
    } finally {
      isLoadingMore.value = false;
    }
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
