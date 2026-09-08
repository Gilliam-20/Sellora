import 'package:get/get.dart';
import '../../../data/models/product_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/product_repository.dart';

class SellerCatalogController extends GetxController {
  final ProductRepository _productRepo = Get.find<ProductRepository>();
  final AuthRepository _authRepo = Get.find<AuthRepository>();

  final catalog = <ProductModel>[].obs;
  final isLoading = true.obs;
  final searchQuery = ''.obs;
  final isListing = false.obs;

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

  Future<bool> listProduct(ProductModel product, double sellPrice) async {
    final user = _authRepo.cachedUser;
    if (user == null) return false;
    isListing.value = true;
    try {
      await _productRepo.listProduct(
          catalogProduct: product, sellerId: user.uid, sellPrice: sellPrice);
      return true;
    } finally {
      isListing.value = false;
    }
  }
}
