import 'package:get/get.dart';
import '../../../data/models/order_model.dart';
import '../../../data/repositories/order_repository.dart';
import '../../storefront/storefront_session.dart';

/// The signed-in customer's orders from this store, newest first.
class BuyerOrdersController extends GetxController {
  BuyerOrdersController({
    String? slug,
    StorefrontSession? session,
    OrderRepository? orders,
  })  : slug = slug ?? Get.parameters['slug'] ?? '',
        session = session ?? Get.find<StorefrontSession>(),
        _orderRepo = orders ?? Get.find<OrderRepository>();

  final String slug;
  final StorefrontSession session;
  final OrderRepository _orderRepo;

  final orders = <OrderModel>[].obs;
  final isLoading = true.obs;
  final error = RxnString();

  @override
  void onInit() {
    super.onInit();
    loadOrders();
  }

  Future<void> loadOrders() async {
    await session.ensure(slug);
    final user = session.customer;
    final store = session.store;
    if (user == null || store == null) {
      // A guest has no orders here; the page offers sign-in instead.
      orders.clear();
      isLoading.value = false;
      return;
    }
    isLoading.value = true;
    error.value = null;
    try {
      orders.value = await _orderRepo.buyerStoreOrders(user.uid, store.id);
    } catch (_) {
      error.value = 'Couldn\'t load your orders. Please try again.';
    } finally {
      isLoading.value = false;
    }
  }
}
