class Validators {
  Validators._();

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter your email';
    final pattern = RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[\w\-]{2,4}$');
    if (!pattern.hasMatch(value.trim())) return 'Enter a valid email address';
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Enter a password';
    if (value.length < 8) return 'Use at least 8 characters';
    return null;
  }

  static String? notEmpty(String? value, {String label = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$label is required';
    return null;
  }

  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter a phone number';
    final digits = value.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.length < 9) return 'Enter a valid phone number';
    return null;
  }

  /// Kenyan M-Pesa numbers via IntaSend expect formats like 2547XXXXXXXX.
  static String? mpesaPhone(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter your M-Pesa number';
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    final normalized = digits.startsWith('0') ? '254${digits.substring(1)}' : digits;
    if (!RegExp(r'^254(7|1)\d{8}$').hasMatch(normalized)) {
      return 'Enter a valid Safaricom number, e.g. 0712345678';
    }
    return null;
  }

  static String? price(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter a price';
    final parsed = double.tryParse(value.trim());
    if (parsed == null || parsed <= 0) return 'Enter a valid amount';
    return null;
  }
}
