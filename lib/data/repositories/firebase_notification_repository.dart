import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../models/notification_model.dart';
import '../models/order_model.dart';
import '../services/firestore_service.dart';
import 'notification_repository.dart';

class FirebaseNotificationRepository extends GetxService
    implements NotificationRepository {
  final FirestoreService _fs = Get.find<FirestoreService>();

  @override
  Stream<List<AppNotification>> watchForUser(String userId) => _fs
      .userNotifications(userId)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => AppNotification.fromMap(doc.data()))
          .toList());

  @override
  Future<void> markRead(String userId, String notificationId) => _fs
      .userNotifications(userId)
      .doc(notificationId)
      .update({'readAt': DateTime.now().toIso8601String()});

  @override
  Future<void> markAllRead(String userId) async {
    final unread = await _fs
        .userNotifications(userId)
        .where('readAt', isNull: true)
        .get();
    final batch = FirebaseFirestore.instance.batch();
    for (final document in unread.docs) {
      batch.update(document.reference, {'readAt': DateTime.now().toIso8601String()});
    }
    await batch.commit();
  }

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

  Future<void> _writeOrderAlerts(OrderModel order,
      {required String buyerTitle,
      required String buyerMessage,
      bool includeSeller = false}) async {
    final batch = FirebaseFirestore.instance.batch();
    _add(batch, order.buyerId, buyerTitle, buyerMessage, order.id);
    if (includeSeller) {
      _add(batch, order.sellerId, 'New order',
          'A new order (${order.code}) is ready to process.', order.id);
    }
    await batch.commit();
  }

  void _add(WriteBatch batch, String recipientId, String title, String message,
      String orderId) {
    final reference = _fs.userNotifications(recipientId).doc();
    batch.set(reference, AppNotification(
      id: reference.id,
      recipientId: recipientId,
      title: title,
      message: message,
      orderId: orderId,
      createdAt: DateTime.now(),
    ).toMap());
  }
}
