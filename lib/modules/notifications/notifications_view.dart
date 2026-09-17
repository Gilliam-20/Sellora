import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_metrics.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/empty_state.dart';
import 'notification_center.dart';

class NotificationsView extends GetView<NotificationCenter> {
  const NotificationsView({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          actions: [
            Obx(() => controller.unreadCount == 0
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: controller.markAllRead,
                    child: const Text('Mark all read'),
                  )),
          ],
        ),
        body: Obx(() {
          if (controller.isLoading.value) {
            return const Center(child: CircularProgressIndicator());
          }
          if (controller.notifications.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_none_outlined,
              title: 'You’re all caught up',
              message: 'Order updates and important account alerts appear here.',
            );
          }
          return ResponsiveCenter(
            maxWidth: 720,
            child: ListView.separated(
              padding: EdgeInsets.symmetric(
                  horizontal: context.pageHorizontalPadding,
                  vertical: AppSpacing.md),
              itemCount: controller.notifications.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final notification = controller.notifications[index];
                return ListTile(
                  onTap: () => controller.markRead(notification),
                  leading: CircleAvatar(
                    backgroundColor: notification.isRead
                        ? AppColors.slateLight
                        : AppColors.buyerAccent.withValues(alpha: 0.18),
                    child: Icon(Icons.notifications_outlined,
                        color: notification.isRead
                            ? AppColors.slate
                            : AppColors.buyerAccent),
                  ),
                  title: Text(notification.title,
                      style: TextStyle(
                          fontWeight: notification.isRead
                              ? FontWeight.w500
                              : FontWeight.w700)),
                  subtitle: Text(
                      '${notification.message}\n${Formatters.date(notification.createdAt)}'),
                  isThreeLine: true,
                  trailing: notification.isRead
                      ? null
                      : const Icon(Icons.circle,
                          size: 10, color: AppColors.buyerAccent),
                );
              },
            ),
          );
        }),
      );
}
