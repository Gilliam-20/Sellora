import 'package:get/get.dart';
import '../../../data/models/order_model.dart';
import '../../../data/repositories/order_repository.dart';

class AdminOrdersController extends GetxController {
  final OrderRepository _orderRepo = Get.find<OrderRepository>();

  final orders = <OrderModel>[].obs;
  final isLoading = true.obs;
  final statusFilter = Rxn<OrderStatus>();

  List<OrderModel> get filtered =>
      statusFilter.value == null ? orders : orders.where((o) => o.status == statusFilter.value).toList();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    orders.value = await _orderRepo.allOrders();
    isLoading.value = false;
  }

  void setFilter(OrderStatus? status) => statusFilter.value = status;
}
