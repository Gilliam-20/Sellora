import 'package:get/get.dart';
import '../../../core/network/api_exception.dart';
import '../../../data/models/order_model.dart';
import '../../../data/models/order_refund_model.dart';
import '../../../data/repositories/order_repository.dart';

class AdminOrdersController extends GetxController {
  final OrderRepository _orderRepo = Get.find<OrderRepository>();

  final orders = <OrderModel>[].obs;
  final isLoading = true.obs;
  final statusFilter = Rxn<OrderStatus>();

  // ---- Refund sheet state ----------------------------------------------
  final refundInfo = Rxn<OrderRefundInfo>();
  final isLoadingRefund = false.obs;
  final isRefunding = false.obs;
  final refundError = RxnString();

  List<OrderModel> get filtered => statusFilter.value == null
      ? orders
      : orders.where((o) => o.status == statusFilter.value).toList();

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

  /// Loads [order]'s refund state for the detail sheet.
  Future<void> openRefund(OrderModel order) async {
    refundInfo.value = null;
    refundError.value = null;
    isLoadingRefund.value = true;
    try {
      refundInfo.value = await _orderRepo.refundInfo(order.id);
      if (refundInfo.value == null) {
        refundError.value = 'Refund details for this order are unavailable.';
      }
    } catch (_) {
      refundError.value = 'Could not load refund details. Try again.';
    } finally {
      isLoadingRefund.value = false;
    }
  }

  /// Checks a typed amount against what's left to refund. Empty means
  /// "refund everything left", which is always valid here.
  String? validateAmount(String text) {
    final info = refundInfo.value;
    if (info == null || text.trim().isEmpty) return null;
    final amount = double.tryParse(text.trim());
    if (amount == null || amount <= 0) return 'Enter a positive amount';
    if (amount - info.remaining > 0.01) {
      return 'Only ${info.remaining.toStringAsFixed(2)} ${info.currency} '
          'is left to refund';
    }
    return null;
  }

  /// Issues the refund. Returns true on success; on failure the server's
  /// message (which is written for an admin) lands in [refundError].
  Future<bool> refund(OrderModel order,
      {required String amountText,
      required String reason,
      required String comment}) async {
    if (isRefunding.value || validateAmount(amountText) != null) return false;
    isRefunding.value = true;
    refundError.value = null;
    try {
      final text = amountText.trim();
      await _orderRepo.refundOrder(order.id,
          amount: text.isEmpty ? null : double.parse(text),
          reason: reason,
          comment: comment.trim());
      await load();
      return true;
    } on ApiException catch (e) {
      refundError.value = e.message;
      // A failed provider call is recorded on the order; show it.
      try {
        refundInfo.value = await _orderRepo.refundInfo(order.id);
      } catch (_) {}
      return false;
    } catch (_) {
      refundError.value = 'The refund could not be sent. Try again.';
      return false;
    } finally {
      isRefunding.value = false;
    }
  }
}
