import 'package:get/get.dart';
import '../../../data/models/product_model.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/fee_repository.dart';
import '../../../data/repositories/product_repository.dart';

class MyListingsController extends GetxController {
  final ProductRepository _productRepo = Get.find<ProductRepository>();
  final AuthRepository _authRepo = Get.find<AuthRepository>();
  final FeeRepository _feeRepo = Get.find<FeeRepository>();

  final listings = <ProductModel>[].obs;
  final isLoading = true.obs;

  /// The service fee in force, for the below-cost warning. The default
  /// until [FeeRepository] answers.
  final feeRate = AppConstants.platformServiceFeeRate.obs;

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
    _loadFeeRate();
    isLoading.value = false;
  }

  Future<void> _loadFeeRate() async {
    try {
      feeRate.value = (await _feeRepo.settings()).serviceFeeRate;
    } catch (_) {
      // Keep the default; it's only a warning's threshold.
    }
  }

  Future<void> unlist(String productId) async {
    final product = listings.firstWhereOrNull((p) => p.id == productId);
    if (product?.storeId == null) return;
    await _productRepo.unlistProduct(product!.storeId!, productId);
    load();
  }

  Future<void> relist(String productId) async {
    final product = listings.firstWhereOrNull((p) => p.id == productId);
    if (product == null) return;
    try {
      await _productRepo.updateListing(product.copyWith(isListed: true));
    } on ListingRejected catch (e) {
      Get.snackbar(
        'Can\'t publish',
        e.reason == ListingRejection.listingLimit
            ? 'Your plan\'s listing limit is reached. Unlist something or upgrade to publish more.'
            : 'Publishing needs an approved account with an active plan.',
      );
    }
    load();
  }
}
