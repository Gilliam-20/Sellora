import '../../core/utils/formatters.dart';
import 'order_model.dart';

/// One row of `order_timeline(order_id)`
/// (supabase/migrations/20261003000300_orders_import_fees.sql): the order's
/// creation, an audited change to its state, or an internal note.
class OrderTimelineEntry {
  OrderTimelineEntry({
    required this.at,
    required this.kind,
    required this.actorRole,
    this.details = const {},
  });

  final DateTime at;

  /// `created`, `change` or `note`.
  final String kind;

  /// Who did it: `buyer` (placing it), `seller`/`admin` (a note), or the
  /// audit log's `user`/`admin`/`service`/`system`.
  final String actorRole;

  /// `created`: `{total, currency}`. `change`: `{column: [old, new]}` for each
  /// column that moved. `note`: `{body}`.
  final Map<String, dynamic> details;

  bool get isNote => kind == 'note';

  String get actorLabel => switch (actorRole) {
        'admin' => 'Sellora',
        'seller' || 'user' => 'You',
        'buyer' => 'Customer',
        _ => 'Sellora',
      };

  /// What happened, as lines to show; empty when a change only touched
  /// something not worth showing on its own.
  List<String> describe({String currency = 'USD'}) {
    switch (kind) {
      case 'created':
        final total = (details['total'] as num?)?.toDouble();
        return [
          total == null
              ? 'Order placed'
              : 'Order placed for ${Formatters.currency(total, code: details['currency'] as String? ?? currency)}',
        ];
      case 'note':
        return [details['body'] as String? ?? ''];
      case 'change':
        final lines = <String>[];
        for (final entry in details.entries) {
          final pair = entry.value;
          if (pair is! List || pair.length != 2) continue;
          final line = _changeLine(entry.key, pair[0], pair[1], currency);
          if (line != null) lines.add(line);
        }
        return lines;
      default:
        return const [];
    }
  }

  static String? _changeLine(
      String column, Object? from, Object? to, String currency) {
    switch (column) {
      case 'status':
        final status = OrderStatus.values
            .where((s) => s.name == to)
            .map((s) => s.label)
            .firstOrNull;
        return status == null ? null : 'Marked ${status.toLowerCase()}';
      case 'payment_status':
        return switch (to) {
          'awaiting_confirmation' => 'Payment started, awaiting confirmation',
          'paid' => 'Payment received',
          'failed' => 'Payment failed',
          'partially_refunded' => 'Partially refunded',
          'refunded' => 'Refunded in full',
          'pending' =>
            from == 'awaiting_confirmation' ? 'Payment not completed' : null,
          _ => null,
        };
      case 'cj_order_status':
        return switch (to) {
          'PUSHED' => 'Sent to CJ Dropshipping for fulfilment',
          'FAILED' => 'CJ Dropshipping didn\'t accept the order; retrying',
          'NEEDS_RECONCILIATION' => 'Held for review by Sellora',
          _ => null,
        };
      case 'tracking_number':
        return to is String && to.isNotEmpty ? 'Tracking number $to' : null;
      case 'refund_status':
        return switch (to) {
          'PROCESSING' => 'Refund started',
          'FAILED' => 'Refund failed',
          _ => null,
        };
      case 'refunded_amount':
        final before = (from as num?)?.toDouble() ?? 0;
        final after = (to as num?)?.toDouble() ?? 0;
        return after > before
            ? 'Refunded ${Formatters.currency(after - before, code: currency)}'
            : null;
      default:
        return null;
    }
  }

  factory OrderTimelineEntry.fromRow(Map<String, dynamic> row) =>
      OrderTimelineEntry(
        at: DateTime.tryParse(row['occurred_at'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
        kind: row['kind'] as String? ?? 'change',
        actorRole: row['actor_role'] as String? ?? 'system',
        details: row['details'] is Map
            ? Map<String, dynamic>.from(row['details'] as Map)
            : const {},
      );
}
