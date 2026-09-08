import 'package:get/get.dart';
import '../../../data/models/product_model.dart';
import '../../../data/repositories/product_repository.dart';

class BuyerHomeController extends GetxController {
  final ProductRepository _productRepo = Get.find<ProductRepository>();

  final products = <ProductModel>[].obs;
  final isLoading = true.obs;
  final selectedCategory = 'All'.obs;
  final searchQuery = ''.obs;

  final categories = const ['All', 'Electronics', 'Fashion', 'Home'];

  @override
  void onInit() {
    super.onInit();
    loadFeed();
  }

  Future<void> loadFeed() async {
    isLoading.value = true;
    products.value = await _productRepo.storefrontFeed(
      keyword: searchQuery.value.isEmpty ? null : searchQuery.value,
      category: selectedCategory.value,
    );
    isLoading.value = false;
  }

  void selectCategory(String category) {
    selectedCategory.value = category;
    loadFeed();
  }

  void search(String query) {
    searchQuery.value = query;
    loadFeed();
  }
}
