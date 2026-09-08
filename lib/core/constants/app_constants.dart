class AppConstants {
  AppConstants._();

  static const String appName = 'Sellora';

  /// When true, the app runs entirely on in-memory mock repositories —
  /// no Firebase project, IntaSend account or CJ Dropshipping key
  /// required. Flip to false once real credentials are wired up in
  /// lib/data/services and InitialBinding. See README.md.
  static const bool useMockData = true;

  static const double defaultCommissionPercent = 5.0; // platform cut per order, on top of the subscription
}

/// Backend endpoints. In production these point at Firebase Cloud
/// Functions (see /functions) that hold the real CJ Dropshipping and
/// IntaSend secret keys — the Flutter app never talks to those APIs
/// directly, so a decompiled app never leaks a secret key.
class ApiEndpoints {
  ApiEndpoints._();

  static const String baseFunctionsUrl = 'https://us-central1-sellora-20.cloudfunctions.net';

  static const String cjSearchProducts = '$baseFunctionsUrl/cjSearchProducts';
  static const String cjProductDetail = '$baseFunctionsUrl/cjProductDetail';
  static const String cjCreateOrder = '$baseFunctionsUrl/cjCreateOrder';
  static const String cjTrackShipment = '$baseFunctionsUrl/cjTrackShipment';

  static const String intasendCollectMpesa = '$baseFunctionsUrl/intasendCollectMpesa';
  static const String intasendCheckout = '$baseFunctionsUrl/intasendCheckout';
  static const String intasendStatus = '$baseFunctionsUrl/intasendStatus';
}
