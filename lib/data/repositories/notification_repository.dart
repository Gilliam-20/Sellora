import '../models/notification_model.dart';
import '../models/order_model.dart';

/// Per-user alerts. Notifications are deliberately stored under the recipient
/// so a buyer can never query another customer's alerts.
abstract class NotificationRepository {
  Stream<List<AppNotification>> watchForUser(String userId);
  Future<void> markRead(String userId, String notificationId);
  Future<void> markAllRead(String userId);
  Future<void> notifyOrderPlaced(OrderModel order);
  Future<void> notifyOrderStatusChanged(OrderModel order);
}
