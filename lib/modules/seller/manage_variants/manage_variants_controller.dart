import 'package:get/get.dart';
import '../../../data/models/product_model.dart';
import '../../../data/repositories/product_repository.dart';
import '../dashboard/seller_dashboard_controller.dart';
import '../my_listings/my_listings_controller.dart';

/// Lets a seller manage the variants of a listing they've already
/// imported — until now [ProductVariant] was import-time-only, set once
/// from CJ Dropshipping and never editable again. Deliberately scoped to
/// what's safe to edit without touching checkout pricing or inventory:
/// a per-variant enable/disable switch (which SKUs a buyer can pick) and a
/// seller-facing SKU label. CJ's own attributes/price/costPrice/image stay
/// read-only — they're supplier-of-record facts, not the seller's to edit.
class ManageVariantsController extends GetxController {
  final ProductRepository _productRepo = Get.find<ProductRepository>();

  late final ProductModel product;
  final variants = <ProductVariant>[].obs;
  final isSaving = false.obs;

  @override
  void onInit() {
    super.onInit();
    product = Get.arguments as ProductModel;
    variants.value = List.of(product.variants);
  }

  void setEnabled(int index, bool enabled) {
    variants[index] = variants[index].copyWith(enabled: enabled);
    variants.refresh();
  }

  void setSku(int index, String sku) {
    variants[index] = variants[index].copyWith(sku: sku);
    variants.refresh();
  }

  Future<bool> save() async {
    isSaving.value = true;
    try {
      await _productRepo
          .updateListing(product.copyWith(variants: List.of(variants)));
      if (Get.isRegistered<MyListingsController>()) {
        Get.find<MyListingsController>().load();
      }
      if (Get.isRegistered<SellerDashboardController>()) {
        Get.find<SellerDashboardController>().load();
      }
      return true;
    } finally {
      isSaving.value = false;
    }
  }
}
