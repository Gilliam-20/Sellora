import 'package:get/get.dart';
import '../../../data/models/cj_category.dart';
import '../../../data/models/product_model.dart';
import '../../../data/repositories/product_repository.dart';

class SellerCatalogController extends GetxController {
  final ProductRepository _productRepo = Get.find<ProductRepository>();

  final catalog = <ProductModel>[].obs;
  final isLoading = true.obs;
  final searchQuery = ''.obs;

  final categories = <CjCategory>[].obs;
  final isLoadingCategories = true.obs;
  final selectedCategoryId = RxnString();

  @override
  void onInit() {
    super.onInit();
    load();
    loadCategories();
  }

  Future<void> load() async {
    isLoading.value = true;
    catalog.value = await _productRepo.browseCatalog(
      keyword: searchQuery.value.isEmpty ? null : searchQuery.value,
      category: selectedCategoryId.value,
    );
    isLoading.value = false;
  }

  Future<void> loadCategories() async {
    isLoadingCategories.value = true;
    try {
      categories.value = await _productRepo.categories();
    } catch (_) {
      // Non-fatal — the chip row just stays empty; keyword search still works.
    } finally {
      isLoadingCategories.value = false;
    }
  }

  void search(String query) {
    searchQuery.value = query;
    load();
  }

  void selectCategory(String categoryId) {
    selectedCategoryId.value =
        selectedCategoryId.value == categoryId ? null : categoryId;
    load();
  }
}
