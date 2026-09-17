class AppNotification {
  const AppNotification({
    required this.id,
    required this.recipientId,
    required this.title,
    required this.message,
    required this.createdAt,
    this.orderId,
    this.readAt,
  });

  final String id;
  final String recipientId;
  final String title;
  final String message;
  final String? orderId;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  factory AppNotification.fromMap(Map<String, dynamic> map) => AppNotification(
        id: map['id'] as String? ?? '',
        recipientId: map['recipientId'] as String? ?? '',
        title: map['title'] as String? ?? 'Notification',
        message: map['message'] as String? ?? '',
        orderId: map['orderId'] as String?,
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
            DateTime.now(),
        readAt: map['readAt'] == null
            ? null
            : DateTime.tryParse(map['readAt'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'recipientId': recipientId,
        'title': title,
        'message': message,
        'orderId': orderId,
        'createdAt': createdAt.toIso8601String(),
        'readAt': readAt?.toIso8601String(),
      };
}
