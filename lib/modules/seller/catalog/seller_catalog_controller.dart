import 'package:get/get.dart';
import '../../../data/models/product_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/repositories/subscription_repository.dart';

class SellerCatalogController extends GetxController {
  final ProductRepository _productRepo = Get.find<ProductRepository>();
  final AuthRepository _authRepo = Get.find<AuthRepository>();
  final SubscriptionRepository _subscriptionRepo =
      Get.find<SubscriptionRepository>();

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

    // Soft, client-side only — listing creation isn't server-authoritative
    // yet (Phase 5's job), so this is an upsell prompt, not real
    // enforcement.
    final plans = await _subscriptionRepo.fetchPlans();
    final plan =
        plans.firstWhereOrNull((p) => p.id == user.subscriptionPlanId);
    if (plan != null && plan.listingLimit != -1) {
      final current = (await _productRepo.sellerListings(user.uid)).length;
      if (current >= plan.listingLimit) {
        Get.snackbar(
          'Listing limit reached',
          'Your ${plan.name} plan allows up to ${plan.listingLimit} listings. Upgrade to list more.',
        );
        return false;
      }
    }

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
