import 'package:get/get.dart';
import '../../../data/models/order_model.dart';
import '../../../data/models/order_timeline.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/repositories/order_repository.dart';
import 'order_filters.dart';
import 'seller_orders_controller.dart';

/// One order, as its seller manages it (TODO.md §14): customer, lines,
/// payment and fee breakdown, shipping and CJ fulfilment, the timeline with
/// internal notes, and the actions the seller may take — ship, deliver, or
/// cancel an unpaid order. Refunds are Sellora's (Admin → Orders), so the
/// seller sees refund state but can't issue one.
class SellerOrderDetailController extends GetxController {
  final OrderRepository _orderRepo = Get.find<OrderRepository>();
  final NotificationRepository _notificationRepo =
      Get.find<NotificationRepository>();

  final order = Rxn<OrderModel>();
  final timeline = <OrderTimelineEntry>[].obs;
  final isLoadingTimeline = true.obs;
  final timelineError = RxnString();
  final isBusy = false.obs;
  final isSavingNote = false.obs;

  @override
  void onInit() {
    super.onInit();
    order.value = Get.arguments as OrderModel?;
    refreshOrder();
  }

  /// Re-reads the order and its timeline. The order passed in is shown
  /// until the fresh copy arrives.
  Future<void> refreshOrder() async {
    final current = order.value;
    if (current == null) return;
    try {
      final fresh = await _orderRepo.sellerOrder(current.id);
      if (fresh != null) order.value = fresh;
    } catch (_) {
      // Keep showing what we have; the timeline reports its own error.
    }
    await loadTimeline();
  }

  Future<void> loadTimeline() async {
    final current = order.value;
    if (current == null) return;
    isLoadingTimeline.value = true;
    timelineError.value = null;
    try {
      // Newest first, the way an activity feed reads.
      timeline.value =
          (await _orderRepo.orderTimeline(current.id)).reversed.toList();
    } catch (e) {
      timelineError.value = 'We couldn\'t load this order\'s history.';
    } finally {
      isLoadingTimeline.value = false;
    }
  }

  OrderStatus? get nextStatus {
    final current = order.value;
    return current == null ? null : SellerOrdersController.nextStatus(current);
  }

  bool get canCancel => order.value?.sellerCanCancel ?? false;

  Future<void> advanceStatus() async {
    final current = order.value;
    final next = nextStatus;
    if (current == null || next == null) return;
    await _run(() async {
      await _orderRepo.updateStatus(current.id, next);
      await _notificationRepo
          .notifyOrderStatusChanged(current.copyWith(status: next));
    }, failure: 'Couldn\'t update the order');
  }

  /// Cancels an order nobody has paid for. The server refuses it if a
  /// payment has started meanwhile.
  Future<void> cancelOrder() async {
    final current = order.value;
    if (current == null || !canCancel) return;
    await _run(() async {
      await _orderRepo.updateStatus(current.id, OrderStatus.cancelled);
      await _notificationRepo.notifyOrderStatusChanged(
          current.copyWith(status: OrderStatus.cancelled));
    },
        failure: 'Couldn\'t cancel the order. A payment may be in progress; '
            'try again in a few minutes');
  }

  /// Returns whether the note was saved.
  Future<bool> addNote(String body) async {
    final current = order.value;
    final text = body.trim();
    if (current == null || text.isEmpty) return false;
    isSavingNote.value = true;
    try {
      await _orderRepo.addOrderNote(current.id, text);
      await loadTimeline();
      return true;
    } catch (e) {
      Get.snackbar('Note not saved', '$e');
      return false;
    } finally {
      isSavingNote.value = false;
    }
  }

  Future<void> _run(Future<void> Function() action,
      {required String failure}) async {
    isBusy.value = true;
    try {
      await action();
      await refreshOrder();
    } catch (e) {
      Get.snackbar(failure, '$e');
    } finally {
      isBusy.value = false;
    }
  }
}
