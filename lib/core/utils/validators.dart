class Validators {
  Validators._();

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter your email';
    // Allows `+` sub-addressing and any TLD length (.online, .agency); the
    // real check is Supabase Auth's, this only catches obvious typos.
    final pattern = RegExp(r"^[\w.+'\-]+@([\w\-]+\.)+[A-Za-z]{2,}$");
    if (!pattern.hasMatch(value.trim())) return 'Enter a valid email address';
    return null;
  }

  /// Sign-in only: an existing password is whatever it is, so the policy
  /// in [newPassword] must not lock out an account created under an older
  /// one (or one set via a password-reset link, which Firebase checks only
  /// against its own minimum).
  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Enter your password';
    return null;
  }

  /// Sign-up policy. Keep in step with the Firebase Auth password policy
  /// configured on the project, if one is set there.
  static String? newPassword(String? value) {
    if (value == null || value.isEmpty) return 'Enter a password';
    if (value.length < 8) return 'Use at least 8 characters';
    if (value.length > 128) return 'Use at most 128 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(value) ||
        !RegExp(r'[0-9]').hasMatch(value)) {
      return 'Use both letters and numbers';
    }
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
    if (value == null || value.trim().isEmpty) {
      return 'Enter your M-Pesa number';
    }
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    final normalized =
        digits.startsWith('0') ? '254${digits.substring(1)}' : digits;
    if (!RegExp(r'^254(7|1)\d{8}$').hasMatch(normalized)) {
      return 'Enter a valid Safaricom number, e.g. 0712345678';
    }
    return null;
  }

  /// Only enforces `#RRGGBB` formatting when [value] is non-empty — this
  /// field (a store's accent color) is optional.
  static String? hexColor(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final pattern = RegExp(r'^#?[0-9A-Fa-f]{6}$');
    if (!pattern.hasMatch(value.trim())) {
      return 'Enter a 6-digit hex color, e.g. #16213E';
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
