import 'dart:math' as math;

import 'package:get/get.dart';
import '../../../core/utils/listing_text.dart';
import '../../../data/models/fee_settings.dart';
import '../../../data/models/freight_estimate.dart';
import '../../../data/models/product_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/fee_repository.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/repositories/subscription_repository.dart';
import '../../storefront/store_scope.dart';
import '../dashboard/seller_dashboard_controller.dart';
import '../my_listings/my_listings_controller.dart';

/// What the seller typed into the import editor's text fields. The view
/// owns the TextEditingControllers; this is their value at submit time.
class ImportDraft {
  const ImportDraft({
    required this.title,
    required this.description,
    required this.sellPrice,
    this.seoTitle = '',
    this.seoDescription = '',
  });

  final String title;
  final String description;
  final double sellPrice;
  final String seoTitle;
  final String seoDescription;
}

/// Drives the CJ → store import editor (TODO.md §13).
///
/// The catalog list only ever has the search-result *summary* of a product
/// (supabase/functions/_shared/cjApi.js's `searchProducts` carries no description and no
/// variants at all), so this re-fetches the full detail before a seller
/// prices anything — that detail call is the only place CJ's real per-SKU
/// `vid`s come from, and they have to reach the listing for checkout to be
/// able to order the right SKU later.
///
/// On top of pricing, the seller picks which images to keep (the first is
/// the main one), which variants to sell and under what SKU, tags and SEO
/// text, and edits the title and description. Collections don't exist yet
/// (PHASE 5), so there is nothing to assign.
class ProductImportController extends GetxController {
  final ProductRepository _productRepo = Get.find<ProductRepository>();
  final AuthRepository _authRepo = Get.find<AuthRepository>();
  final SubscriptionRepository _subscriptionRepo =
      Get.find<SubscriptionRepository>();
  final FeeRepository _feeRepo = Get.find<FeeRepository>();
  final StoreScope _storeScope = Get.find<StoreScope>();

  final product = Rxn<ProductModel>();
  final selectedVariant = Rxn<ProductVariant>();
  final previewImage = ''.obs;

  /// Every image CJ offers for the product, in CJ's order.
  final availableImages = <String>[].obs;

  /// The images the listing keeps, in display order; the first is the main
  /// image.
  final selectedImages = <String>[].obs;

  /// Variants the buyer may pick, by `vid`. All of them by default.
  final enabledVids = <String>{}.obs;

  /// The seller's own SKU per `vid`, where they replaced CJ's.
  final skuOverrides = <String, String>{}.obs;

  final tags = <String>[].obs;

  /// The fee in force, for the earnings preview and price floor. Checkout
  /// charges whatever the server reads at the time; this is a preview.
  final fees = FeeSettings.defaults.obs;

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
    _resetImages(_summary);
    loadDetail();
    _loadFees();
  }

  Future<void> _loadFees() async {
    try {
      fees.value = await _feeRepo.settings();
    } catch (_) {
      // The default rate is a fine preview; checkout uses the real one.
    }
  }

  Future<void> loadDetail() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final detail = await _productRepo.productDetail(_summary.id);
      product.value = detail;
      if (detail.imageUrl.isNotEmpty) previewImage.value = detail.imageUrl;
      _resetImages(detail);
      enabledVids
        ..clear()
        ..addAll(detail.variants.map((v) => v.vid));
      skuOverrides.clear();
      if (detail.variants.isNotEmpty) selectVariant(detail.variants.first);
    } catch (e) {
      errorMessage.value =
          'We couldn\'t load this product from CJ Dropshipping. $e';
    } finally {
      isLoading.value = false;
    }
  }

  void _resetImages(ProductModel source) {
    final all = <String>{
      source.imageUrl,
      ...source.images,
      ...source.variants.map((v) => v.image ?? ''),
    }.where((url) => url.isNotEmpty).toList();
    availableImages.assignAll(all);
    selectedImages.assignAll(all);
  }

  void selectVariant(ProductVariant variant) {
    selectedVariant.value = variant;
    final image = variant.image;
    if (image != null && image.isNotEmpty) previewImage.value = image;
    _loadShippingEstimate();
  }

  void showImage(String url) => previewImage.value = url;

  // ---- Images ------------------------------------------------------------

  /// Keeps or drops [url]. The last kept image can't be dropped: a listing
  /// needs a picture.
  void toggleImage(String url) {
    if (selectedImages.contains(url)) {
      if (selectedImages.length == 1) return;
      selectedImages.remove(url);
    } else {
      // Back in CJ's order, so re-adding doesn't shuffle the gallery.
      final order = availableImages.toList();
      selectedImages
        ..add(url)
        ..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
    }
  }

  /// Moves [url] to the front, making it the main image.
  void makeMainImage(String url) {
    if (!selectedImages.contains(url)) return;
    selectedImages
      ..remove(url)
      ..insert(0, url);
    previewImage.value = url;
  }

  // ---- Variants ----------------------------------------------------------

  bool isVariantEnabled(ProductVariant v) => enabledVids.contains(v.vid);

  /// Turns [variant] on or off for buyers. At least one stays on.
  void toggleVariant(ProductVariant variant) {
    if (enabledVids.contains(variant.vid)) {
      if (enabledVids.length == 1) return;
      enabledVids.remove(variant.vid);
    } else {
      enabledVids.add(variant.vid);
    }
  }

  String skuFor(ProductVariant variant) =>
      skuOverrides[variant.vid] ?? variant.sku;

  /// A blank SKU means "use CJ's".
  void setSku(ProductVariant variant, String sku) {
    final trimmed = sku.trim();
    if (trimmed.isEmpty || trimmed == variant.sku) {
      skuOverrides.remove(variant.vid);
    } else {
      skuOverrides[variant.vid] = trimmed;
    }
  }

  // ---- Tags --------------------------------------------------------------

  void addTags(String input) => tags.assignAll(
      ListingText.addTags(tags, input, limit: ProductModel.maxTags));

  void removeTag(String tag) => tags.remove(tag);

  // ---- Pricing -----------------------------------------------------------

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

  double get feeRate => fees.value.serviceFeeRate;

  /// What the seller keeps from one sale at [price]: the price less
  /// Sellora's service fee, less CJ's cost of the goods. Shipping isn't in
  /// it — the buyer pays that separately at checkout, and the freight margin
  /// is Sellora's (the H1 decision, SELLORA_SECURITY_AUDIT.md §6). When an
  /// admin has set the fee to take shipping too, that part comes out of the
  /// seller's share as well. Mirrors `splitServiceFee` in
  /// supabase/functions/_shared/orders.js.
  double sellerEarning(double price) =>
      price - fees.value.feeOn(price, shipping: shippingCost) - costPrice;

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

  /// The lowest price checkout will sell this listing at: after the
  /// service fee it must still cover CJ's cost of the dearest variant the
  /// seller keeps on, since one price covers them all. The server applies
  /// the same floor to CJ's live cost at checkout (`lineRefusal` in
  /// supabase/functions/_shared/orders.js); this catches it before import.
  double get priceFloor {
    final full = product.value;
    if (full == null) return 0;
    final kept = full.variants.where(isVariantEnabled).map((v) => v.costPrice);
    final dearest = kept.fold(full.variants.isEmpty ? full.costPrice : 0.0,
        math.max);
    return (dearest / (1 - feeRate) * 100).ceil() / 100;
  }

  /// The price whose [sellerEarning] (goods only) is [marginPercent] of
  /// CJ's cost, i.e. after the service fee, rounded up to the cent.
  double priceForMargin(double marginPercent) =>
      (costPrice * (1 + marginPercent / 100) / (1 - feeRate) * 100).ceil() /
      100;

  /// The listing as the seller has edited it: [ImportDraft]'s text, the
  /// kept images (first is the main one), variants with their on/off state
  /// and SKU overrides, and tags.
  ProductModel buildListing(ProductModel full, ImportDraft draft) {
    final images = selectedImages.isNotEmpty
        ? selectedImages.toList()
        : availableImages.toList();
    return full.copyWith(
      title: draft.title.trim(),
      description: draft.description.trim(),
      imageUrl: images.isNotEmpty ? images.first : full.imageUrl,
      images: images,
      variants: full.variants
          .map((v) => v.copyWith(
                enabled: isVariantEnabled(v),
                sku: skuFor(v),
              ))
          .toList(),
      tags: tags.toList(),
      seoTitle: draft.seoTitle.trim(),
      seoDescription: draft.seoDescription.trim(),
    );
  }

  /// Writes the listing. Returns false when it was blocked (no session, or
  /// the plan's listing limit is already reached — which snackbars its own
  /// upsell).
  Future<bool> import(ImportDraft draft, {required bool publish}) async {
    final user = _authRepo.cachedUser;
    final full = product.value;
    final storeId = _storeScope.current.value?.id;
    if (user == null || full == null || storeId == null) return false;

    // An early upsell prompt. The limit itself is enforced server-side (a
    // trigger on `products`), which counts published listings only.
    final plans = await _subscriptionRepo.fetchPlans();
    final plan = plans.firstWhereOrNull((p) => p.id == user.subscriptionPlanId);
    if (publish && plan != null && plan.listingLimit != -1) {
      final listed = (await _productRepo.sellerListings(user.uid))
          .where((p) => p.isListed)
          .length;
      if (listed >= plan.listingLimit) {
        _listingLimitReached(plan.name, plan.listingLimit);
        return false;
      }
    }

    isSubmitting.value = true;
    try {
      await _productRepo.listProduct(
        catalogProduct: buildListing(full, draft),
        storeId: storeId,
        sellerId: user.uid,
        sellPrice: draft.sellPrice,
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
    } on ListingRejected catch (e) {
      switch (e.reason) {
        case ListingRejection.listingLimit:
          _listingLimitReached(plan?.name, plan?.listingLimit);
        case ListingRejection.notInGoodStanding:
          Get.snackbar(
            'Can\'t publish yet',
            'Publishing needs an approved account with an active plan. '
                'You can still save this as a draft.',
          );
      }
      return false;
    } finally {
      isSubmitting.value = false;
    }
  }

  void _listingLimitReached(String? planName, int? limit) {
    Get.snackbar(
      'Listing limit reached',
      planName == null || limit == null
          ? 'Your plan\'s listing limit is reached. Upgrade to list more.'
          : 'Your $planName plan allows up to $limit listings. Upgrade to list more.',
    );
  }
}
