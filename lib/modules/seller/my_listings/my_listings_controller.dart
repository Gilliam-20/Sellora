import 'package:get/get.dart';
import '../../../data/models/product_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/product_repository.dart';

class MyListingsController extends GetxController {
  final ProductRepository _productRepo = Get.find<ProductRepository>();
  final AuthRepository _authRepo = Get.find<AuthRepository>();

  final listings = <ProductModel>[].obs;
  final isLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    final user = _authRepo.cachedUser;
    if (user == null) return;
    isLoading.value = true;
    listings.value = await _productRepo.sellerListings(user.uid);
    isLoading.value = false;
  }

  Future<void> unlist(String productId) async {
    await _productRepo.unlistProduct(productId);
    load();
  }
}
