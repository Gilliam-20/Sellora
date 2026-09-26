import 'package:get/get.dart';
import '../../../data/models/freight_estimate.dart';
import '../../../data/models/product_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/repositories/subscription_repository.dart';
import '../../storefront/store_scope.dart';
import '../dashboard/seller_dashboard_controller.dart';
import '../my_listings/my_listings_controller.dart';

/// Drives the CJ product detail + import screen.
///
/// The catalog list only ever has the search-result *summary* of a product
/// (supabase/functions/_shared/cjApi.js's `searchProducts` carries no description and no
/// variants at all), so this re-fetches the full detail before a seller
/// prices anything — that detail call is the only place CJ's real per-SKU
/// `vid`s come from, and they have to reach the listing for checkout to be
/// able to order the right SKU later.
class ProductImportController extends GetxController {
  final ProductRepository _productRepo = Get.find<ProductRepository>();
  final AuthRepository _authRepo = Get.find<AuthRepository>();
  final SubscriptionRepository _subscriptionRepo =
      Get.find<SubscriptionRepository>();
  final StoreScope _storeScope = Get.find<StoreScope>();

  final product = Rxn<ProductModel>();
  final selectedVariant = Rxn<ProductVariant>();
  final previewImage = ''.obs;

  final isLoading = true.obs;
  final errorMessage = RxnString();
  final isSubmitting = false.obs;

  final shippingEstimate = Rxn<FreightEstimate>();
  final isLoadingShipping = false.obs;
  final shippingError = RxnString();

  late final ProductModel _summary;

  @override
  void onInit() {
    super.onInit();
    _summary = Get.arguments as ProductModel;
    // Render the summary immediately so the screen never starts blank,
    // then swap in the full detail once it arrives.
    product.value = _summary;
    previewImage.value = _summary.imageUrl;
    loadDetail();
  }

  Future<void> loadDetail() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final detail = await _productRepo.productDetail(_summary.id);
      product.value = detail;
      if (detail.imageUrl.isNotEmpty) previewImage.value = detail.imageUrl;
      if (detail.variants.isNotEmpty) selectVariant(detail.variants.first);
    } catch (e) {
      errorMessage.value =
          'We couldn\'t load this product from CJ Dropshipping. $e';
    } finally {
      isLoading.value = false;
    }
  }

  void selectVariant(ProductVariant variant) {
    selectedVariant.value = variant;
    final image = variant.image;
    if (image != null && image.isNotEmpty) previewImage.value = image;
    _loadShippingEstimate();
  }

  void showImage(String url) => previewImage.value = url;

  Future<void> _loadShippingEstimate() async {
    final vid = selectedVariant.value?.vid;
    if (vid == null || vid.isEmpty) {
      shippingEstimate.value = null;
      return;
    }
    isLoadingShipping.value = true;
    shippingError.value = null;
    try {
      shippingEstimate.value = await _productRepo.estimateShipping(vid: vid);
    } catch (e) {
      shippingError.value = 'Shipping estimate unavailable';
      shippingEstimate.value = null;
    } finally {
      isLoadingShipping.value = false;
    }
  }

  /// What the margin calculator prices against — the selected SKU's own CJ
  /// supplier price when it has one, since sizes/colors of the same product
  /// routinely cost different amounts.
  double get costPrice {
    final variantCost = selectedVariant.value?.costPrice ?? 0;
    if (variantCost > 0) return variantCost;
    return product.value?.costPrice ?? 0;
  }

  double get shippingCost => shippingEstimate.value?.cost ?? 0;

  /// CJ cost + estimated shipping to Kenya — the basis the quick-margin
  /// presets and the live profit/margin readout price against (landed cost,
  /// not bare CJ cost). Local to this screen only — doesn't touch
  /// ProductModel.costPrice/marginPercent, which stay CJ-cost-only
  /// elsewhere (e.g. the dashboard).
  double get landedCost => costPrice + shippingCost;

  /// CJ's own suggested retail for the current selection — already
  /// margin-priced server-side (supabase/functions/_shared/marginPricingService.js), so
  /// it's the most sensible default to pre-fill rather than a made-up
  /// multiple of cost.
  double get suggestedRetailPrice {
    final variantPrice = selectedVariant.value?.price ?? 0;
    if (variantPrice > 0) return variantPrice;
    final productPrice = product.value?.sellPrice ?? 0;
    if (productPrice > 0) return productPrice;
    return priceForMargin(30); // no CJ price signal at all — fall back to a 30% default margin
  }

  String get currencyCode => product.value?.currency ?? 'USD';

  /// The price that yields [marginPercent] over [landedCost] (CJ cost +
  /// estimated shipping), not just bare CJ cost — an accurate margin has to
  /// account for what it actually costs to get the item to a buyer.
  double priceForMargin(double marginPercent) =>
      landedCost * (1 + marginPercent / 100);

  /// Writes the listing. Returns false when it was blocked (no session, or
  /// the plan's listing limit is already reached — which snackbars its own
  /// upsell).
  Future<bool> import({required double sellPrice, required bool publish}) async {
    final user = _authRepo.cachedUser;
    final full = product.value;
    final storeId = _storeScope.current.value?.id;
    if (user == null || full == null || storeId == null) return false;

    // Soft, client-side only — listing creation isn't server-authoritative
    // yet (Phase 5's job), so this is an upsell prompt, not real
    // enforcement.
    final plans = await _subscriptionRepo.fetchPlans();
    final plan = plans.firstWhereOrNull((p) => p.id == user.subscriptionPlanId);
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

    isSubmitting.value = true;
    try {
      await _productRepo.listProduct(
        catalogProduct: full,
        storeId: storeId,
        sellerId: user.uid,
        sellPrice: sellPrice,
        isListed: publish,
      );
      // My listings/dashboard tabs are built once into the shell's
      // IndexedStack (see SellerShellView) and only load their data in
      // onInit — without this they'd keep showing pre-import data until
      // the whole seller shell is torn down and rebuilt.
      if (Get.isRegistered<MyListingsController>()) {
        Get.find<MyListingsController>().load();
      }
      if (Get.isRegistered<SellerDashboardController>()) {
        Get.find<SellerDashboardController>().load();
      }
      return true;
    } finally {
      isSubmitting.value = false;
    }
  }
}
