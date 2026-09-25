import 'package:get/get.dart';

import '../models/notification_model.dart';
import '../models/order_model.dart';
import '../services/supabase_service.dart';
import 'notification_repository.dart';

class SupabaseNotificationRepository extends GetxService
    implements NotificationRepository {
  final SupabaseService _db = Get.find<SupabaseService>();

  /// Realtime: `notifications` is in the supabase_realtime publication, and
  /// Realtime applies the same RLS as a plain select.
  @override
  Stream<List<AppNotification>> watchForUser(String userId) => _db.notifications
      .stream(primaryKey: ['id'])
      .eq('recipient_id', userId)
      .order('created_at', ascending: false)
      .map((rows) =>
          rows.map((row) => AppNotification.fromMap(fromRow(row))).toList());

  @override
  Future<void> markRead(String userId, String notificationId) =>
      _db.notifications
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('recipient_id', userId)
          .eq('id', notificationId);

  @override
  Future<void> markAllRead(String userId) => _db.notifications
      .update({'read_at': DateTime.now().toUtc().toIso8601String()})
      .eq('recipient_id', userId)
      .isFilter('read_at', null);

  @override
  Future<void> notifyOrderPlaced(OrderModel order) => _writeOrderAlerts(
        order,
        buyerTitle: 'Order placed',
        buyerMessage: 'Your order ${order.code} has been received.',
        includeSeller: true,
      );

  @override
  Future<void> notifyOrderStatusChanged(OrderModel order) => _writeOrderAlerts(
        order,
        buyerTitle: 'Order update',
        buyerMessage:
            'Order ${order.code} is now ${order.status.label.toLowerCase()}.',
      );

  /// One insert for both alerts, so they land together or not at all, as
  /// the Firestore batch did. Deliberately no `.select()`: returning the
  /// rows would apply the read policy too, and the counterparty's alert
  /// isn't readable by the sender, so the whole insert would be refused.
  Future<void> _writeOrderAlerts(OrderModel order,
      {required String buyerTitle,
      required String buyerMessage,
      bool includeSeller = false}) async {
    await _db.notifications.insert([
      _row(order.buyerId, buyerTitle, buyerMessage, order.id),
      if (includeSeller)
        _row(order.sellerId, 'New order',
            'A new order (${order.code}) is ready to process.', order.id),
    ]);
  }

  Map<String, dynamic> _row(
      String recipientId, String title, String message, String orderId) {
    return toRow(
      AppNotification(
        id: '',
        recipientId: recipientId,
        title: title,
        message: message,
        orderId: orderId,
        createdAt: DateTime.now(),
      ).toMap(),
      // The database generates the id.
      omit: const {'id'},
    );
  }
}
