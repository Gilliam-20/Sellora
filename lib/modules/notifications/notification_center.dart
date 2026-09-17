import 'dart:async';

import 'package:get/get.dart';

import '../../data/models/notification_model.dart';
import '../../data/repositories/notification_repository.dart';

/// Shared inbox state for the notification tab and shell badge.
class NotificationCenter extends GetxService {
  NotificationCenter({NotificationRepository? repository})
      : _repository = repository ?? Get.find<NotificationRepository>();

  final NotificationRepository _repository;
  final notifications = <AppNotification>[].obs;
  final isLoading = false.obs;
  StreamSubscription<List<AppNotification>>? _subscription;
  String? _userId;

  int get unreadCount => notifications.where((item) => !item.isRead).length;

  void start(String userId) {
    if (_userId == userId) return;
    _subscription?.cancel();
    _userId = userId;
    isLoading.value = true;
    _subscription = _repository.watchForUser(userId).listen((items) {
      notifications.value = items;
      isLoading.value = false;
    }, onError: (_) => isLoading.value = false);
  }

  Future<void> markRead(AppNotification notification) async {
    final userId = _userId;
    if (userId == null || notification.isRead) return;
    await _repository.markRead(userId, notification.id);
  }

  Future<void> markAllRead() async {
    final userId = _userId;
    if (userId != null) await _repository.markAllRead(userId);
  }

  @override
  void onClose() {
    _subscription?.cancel();
    super.onClose();
  }
}
