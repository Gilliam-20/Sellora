import 'package:get/get.dart';

import '../../../core/utils/store_link.dart';
import '../../../data/models/discount_model.dart';
import '../../../data/models/product_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/discount_repository.dart';
import '../../../data/repositories/product_repository.dart';
import '../../storefront/store_scope.dart';

/// The seller's Marketing screen (TODO.md §26/§27): their store's discount
/// codes, and a link to share the storefront.
class SellerMarketingController extends GetxController {
  SellerMarketingController({
    DiscountRepository? discountRepository,
    ProductRepository? productRepository,
    AuthRepository? authRepository,
    StoreScope? scope,
  })  : _discounts = discountRepository ?? Get.find<DiscountRepository>(),
        _products = productRepository ?? Get.find<ProductRepository>(),
        _auth = authRepository ?? Get.find<AuthRepository>(),
        scope = scope ?? Get.find<StoreScope>();

  final DiscountRepository _discounts;
  final ProductRepository _products;
  final AuthRepository _auth;
  final StoreScope scope;

  final isLoading = true.obs;
  final errorMessage = RxnString();
  final discounts = <DiscountModel>[].obs;

  /// Live orders per discount id.
  final usage = <String, int>{}.obs;

  /// The seller's listings, for limiting a code to some products.
  final listings = <ProductModel>[].obs;

  String? get storeId => scope.current.value?.id;

  Uri? get storeLink {
    final slug = scope.current.value?.slug;
    return slug == null ? null : storefrontLink(slug);
  }

  String get shareMessage =>
      'Shop ${scope.current.value?.name ?? 'my store'} on Sellora:';

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    final id = storeId;
    final user = _auth.cachedUser;
    if (id == null || user == null) {
      errorMessage.value = 'Your store isn\'t loaded yet.';
      isLoading.value = false;
      return;
    }
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final results = await Future.wait([
        _discounts.storeDiscounts(id),
        _discounts.usage(id),
        _products.sellerListings(user.uid),
      ]);
      discounts.assignAll(results[0] as List<DiscountModel>);
      usage.assignAll(results[1] as Map<String, int>);
      listings.assignAll((results[2] as List<ProductModel>)
          .where((p) => p.storeId == null || p.storeId == id));
    } catch (_) {
      errorMessage.value = 'Couldn\'t load your discount codes.';
    } finally {
      isLoading.value = false;
    }
  }

  int usesOf(DiscountModel discount) => usage[discount.id] ?? 0;

  DiscountStatus statusOf(DiscountModel discount) =>
      discount.statusAt(DateTime.now(), uses: usesOf(discount));

  /// Creates or updates [discount]. Returns an error to show, or null.
  Future<String?> save(DiscountModel discount) async {
    final problem = validate(discount);
    if (problem != null) return problem;
    try {
      if (discount.id.isEmpty) {
        final created = await _discounts.createDiscount(discount);
        discounts.insert(0, created);
      } else {
        await _discounts.updateDiscount(discount);
        final index = discounts.indexWhere((d) => d.id == discount.id);
        if (index >= 0) discounts[index] = discount;
      }
      return null;
    } on DuplicateDiscountCodeException catch (e) {
      return e.toString();
    } catch (_) {
      return 'Couldn\'t save this code. Please try again.';
    }
  }

  Future<String?> setActive(DiscountModel discount, bool active) =>
      save(discount.copyWith(isActive: active));

  /// Returns an error to show, or null once deleted.
  Future<String?> delete(DiscountModel discount) async {
    try {
      await _discounts.deleteDiscount(discount.id);
      discounts.removeWhere((d) => d.id == discount.id);
      return null;
    } on DiscountInUseException catch (e) {
      return e.toString();
    } catch (_) {
      return 'Couldn\'t delete this code. Please try again.';
    }
  }

  /// The same rules as the `discounts` table's checks, so a bad code is
  /// caught before the round trip.
  static String? validate(DiscountModel d) {
    if (!DiscountModel.codePattern.hasMatch(d.code)) {
      return 'Use 3–32 letters, numbers, - or _ for the code.';
    }
    if (d.value <= 0) return 'Enter how much the code takes off.';
    if (d.kind == DiscountKind.percentage && d.value > 100) {
      return 'A percentage can\'t be more than 100.';
    }
    if (d.minSubtotal < 0) return 'The minimum order can\'t be negative.';
    if (d.endsAt != null && !d.endsAt!.isAfter(d.startsAt)) {
      return 'The end date must be after the start date.';
    }
    if (d.usageLimit != null && d.usageLimit! < 1) {
      return 'The usage limit must be at least 1.';
    }
    return null;
  }
}
