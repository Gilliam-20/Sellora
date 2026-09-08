import 'package:get/get.dart';
import '../../../data/models/order_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../data/repositories/product_repository.dart';

class SellerDashboardController extends GetxController {
  final OrderRepository _orderRepo = Get.find<OrderRepository>();
  final ProductRepository _productRepo = Get.find<ProductRepository>();
  final AuthRepository authRepo = Get.find<AuthRepository>();

  final isLoading = true.obs;
  final recentOrders = <OrderModel>[].obs;
  final listingCount = 0.obs;
  final totalRevenue = 0.0.obs;
  final pendingCount = 0.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    final user = authRepo.cachedUser;
    if (user == null) return;
    isLoading.value = true;

    final orders = await _orderRepo.sellerOrders(user.uid);
    final listings = await _productRepo.sellerListings(user.uid);

    recentOrders.value = orders.take(5).toList();
    listingCount.value = listings.where((l) => l.isListed).length;
    totalRevenue.value = orders.fold(0.0, (sum, o) => sum + o.total);
    pendingCount.value = orders
        .where((o) =>
            o.status == OrderStatus.pending ||
            o.status == OrderStatus.processing)
        .length;

    isLoading.value = false;
  }
}
