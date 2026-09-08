import 'package:get/get.dart';
import '../../../data/models/product_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/repositories/store_repository.dart';

class BuyerHomeController extends GetxController {
  final ProductRepository _productRepo = Get.find<ProductRepository>();
  final StoreRepository _storeRepo = Get.find<StoreRepository>();
  final AuthRepository _authRepo = Get.find<AuthRepository>();

  final products = <ProductModel>[].obs;
  final isLoading = true.obs;
  final selectedCategory = 'All'.obs;
  final searchQuery = ''.obs;
  final storeName = 'Sellora'.obs;

  String? _storeSellerId;

  final categories = const ['All', 'Electronics', 'Fashion', 'Home'];

  @override
  void onInit() {
    super.onInit();
    loadFeed();
  }

  Future<void> loadFeed() async {
    isLoading.value = true;

    // A buyer belongs to exactly one store — show that store's own
    // listings (what the seller dashboard already reads) instead of the
    // old cross-seller marketplace feed, so the tenant boundary actually
    // shows up in the UI.
    if (_storeSellerId == null) {
      final storeId = _authRepo.cachedUser?.storeId;
      if (storeId != null) {
        final store = await _storeRepo.storeById(storeId);
        if (store != null) {
          _storeSellerId = store.sellerId;
          storeName.value = store.name;
        }
      }
    }

    final source = _storeSellerId != null
        ? await _productRepo.sellerListings(_storeSellerId!)
        : await _productRepo.storefrontFeed();

    final keyword = searchQuery.value.trim().toLowerCase();
    products.value = source.where((p) {
      final matchesKeyword =
          keyword.isEmpty || p.title.toLowerCase().contains(keyword);
      final matchesCategory = selectedCategory.value == 'All' ||
          p.category == selectedCategory.value;
      return p.isListed && matchesKeyword && matchesCategory;
    }).toList();

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
