import 'dart:async';

import 'package:get/get.dart';

import '../../models/notification_model.dart';
import '../../models/order_model.dart';
import '../notification_repository.dart';

class MockNotificationRepository extends GetxService
    implements NotificationRepository {
  final List<AppNotification> _notifications = [];
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<List<AppNotification>> watchForUser(String userId) async* {
    yield _forUser(userId);
    await for (final _ in _changes.stream) {
      yield _forUser(userId);
    }
  }

  List<AppNotification> _forUser(String userId) => _notifications
      .where((notification) => notification.recipientId == userId)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<void> markRead(String userId, String notificationId) async {
    final index = _notifications.indexWhere(
        (item) => item.id == notificationId && item.recipientId == userId);
    if (index == -1 || _notifications[index].isRead) return;
    final item = _notifications[index];
    _notifications[index] = AppNotification(
      id: item.id,
      recipientId: item.recipientId,
      title: item.title,
      message: item.message,
      orderId: item.orderId,
      createdAt: item.createdAt,
      readAt: DateTime.now(),
    );
    _changes.add(null);
  }

  @override
  Future<void> markAllRead(String userId) async {
    for (final item in List<AppNotification>.from(_notifications)) {
      if (!item.isRead && item.recipientId == userId) {
        await markRead(userId, item.id);
      }
    }
  }

  @override
  Future<void> notifyOrderPlaced(OrderModel order) async {
    _add(order.buyerId, 'Order placed',
        'Your order ${order.code} has been received.', order.id);
    _add(order.sellerId, 'New order',
        'A new order (${order.code}) is ready to process.', order.id);
  }

  @override
  Future<void> notifyOrderStatusChanged(OrderModel order) async {
    _add(order.buyerId, 'Order update',
        'Order ${order.code} is now ${order.status.label.toLowerCase()}.',
        order.id);
  }

  void _add(String recipientId, String title, String message, String orderId) {
    _notifications.add(AppNotification(
      id: 'notification-${DateTime.now().microsecondsSinceEpoch}',
      recipientId: recipientId,
      title: title,
      message: message,
      orderId: orderId,
      createdAt: DateTime.now(),
    ));
    _changes.add(null);
  }
}
