import 'package:intl/intl.dart';

class Formatters {
  Formatters._();

  /// Sellora stores all prices in the seller's chosen currency code
  /// alongside the amount (see [ProductModel.currency]); this formats
  /// using that code so a Nairobi seller sees KES and a US seller sees USD.
  static String currency(double amount, {String code = 'USD'}) {
    final symbol = switch (code) {
      'KES' => 'KSh ',
      'USD' => r'$',
      'EUR' => '€',
      'GBP' => '£',
      _ => '$code ',
    };
    final formatted = NumberFormat('#,##0.00').format(amount);
    return '$symbol$formatted';
  }

  static String date(DateTime date) => DateFormat('MMM d, y').format(date);

  static String dateTime(DateTime date) => DateFormat('MMM d, y · h:mm a').format(date);

  static String relative(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return date_(date);
  }

  static String date_(DateTime date) => DateFormat('MMM d').format(date);

  /// Normalizes a local Kenyan number (07... or +2547...) to the
  /// 2547XXXXXXXX format IntaSend's M-Pesa STK push expects.
  static String toMpesaFormat(String rawPhone) {
    var digits = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0')) digits = '254${digits.substring(1)}';
    if (digits.startsWith('7') || digits.startsWith('1')) digits = '254$digits';
    return digits;
  }
}
