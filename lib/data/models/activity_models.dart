/// One row of the append-only `audit_logs` table: who changed what. Written
/// by triggers and the api function (supabase/migrations/
/// 20260928000000_security_hardening.sql); admin reads only.
class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.occurredAt,
    required this.actorRole,
    required this.action,
    required this.entityType,
    required this.entityId,
    this.actorId,
    this.details = const {},
  });

  final int id;
  final DateTime occurredAt;
  final String? actorId;

  /// 'admin' | 'user' | 'service' | 'system'.
  final String actorRole;

  /// e.g. `store.update`, `order.refund`.
  final String action;
  final String entityType;
  final String entityId;
  final Map<String, dynamic> details;

  /// The changed field names, for audit rows that record `{changes: {field:
  /// [old, new]}}`.
  List<String> get changedFields {
    final changes = details['changes'];
    return changes is Map ? changes.keys.cast<String>().toList() : const [];
  }

  factory AuditLogEntry.fromMap(Map<String, dynamic> map) => AuditLogEntry(
        id: (map['id'] as num).toInt(),
        occurredAt: DateTime.tryParse(map['occurredAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        actorId: map['actorId'] as String?,
        actorRole: map['actorRole'] as String? ?? 'system',
        action: map['action'] as String? ?? '',
        entityType: map['entityType'] as String? ?? '',
        entityId: map['entityId'] as String? ?? '',
        details: map['details'] is Map
            ? Map<String, dynamic>.from(map['details'] as Map)
            : const {},
      );
}

/// An uncaught app error, as `report_client_error` stored it
/// (supabase/migrations/20261003000200_admin_platform.sql).
class ClientErrorReport {
  const ClientErrorReport({
    required this.id,
    required this.occurredAt,
    required this.fingerprint,
    required this.message,
    this.userId,
    this.stack,
    this.context = const {},
  });

  final int id;
  final DateTime occurredAt;
  final String? userId;

  /// Same for every report whose message starts with the same line.
  final String fingerprint;
  final String message;
  final String? stack;
  final Map<String, dynamic> context;

  String get headline => message.split('\n').first;

  factory ClientErrorReport.fromMap(Map<String, dynamic> map) =>
      ClientErrorReport(
        id: (map['id'] as num).toInt(),
        occurredAt: DateTime.tryParse(map['occurredAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        userId: map['userId'] as String?,
        fingerprint: map['fingerprint'] as String? ?? '',
        message: map['message'] as String? ?? '',
        stack: map['stack'] as String?,
        context: map['context'] is Map
            ? Map<String, dynamic>.from(map['context'] as Map)
            : const {},
      );
}

/// Reports of one error grouped by [ClientErrorReport.fingerprint], newest
/// first, for the admin Activity screen.
class ClientErrorGroup {
  ClientErrorGroup(this.reports);

  /// Newest first; never empty.
  final List<ClientErrorReport> reports;

  ClientErrorReport get latest => reports.first;
  int get count => reports.length;

  /// Distinct signed-in users who hit it (signed-out visitors aren't
  /// counted, they have no id).
  int get affectedUsers =>
      reports.map((r) => r.userId).whereType<String>().toSet().length;

  static List<ClientErrorGroup> group(Iterable<ClientErrorReport> reports) {
    final byFingerprint = <String, List<ClientErrorReport>>{};
    final sorted = reports.toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    for (final report in sorted) {
      byFingerprint.putIfAbsent(report.fingerprint, () => []).add(report);
    }
    return byFingerprint.values.map(ClientErrorGroup.new).toList();
  }
}
