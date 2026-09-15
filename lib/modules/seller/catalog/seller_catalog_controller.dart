import 'package:get/get.dart';
import '../../../data/models/product_model.dart';
import '../../../data/repositories/product_repository.dart';

class SellerCatalogController extends GetxController {
  final ProductRepository _productRepo = Get.find<ProductRepository>();

  final catalog = <ProductModel>[].obs;
  final isLoading = true.obs;
  final searchQuery = ''.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    catalog.value = await _productRepo.browseCatalog(
        keyword: searchQuery.value.isEmpty ? null : searchQuery.value);
    isLoading.value = false;
  }

  void search(String query) {
    searchQuery.value = query;
    load();
  }
}
