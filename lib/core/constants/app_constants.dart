class AppConstants {
  AppConstants._();

  static const String appName = 'Sellora';

  /// When true, the app runs entirely on in-memory mock repositories —
  /// no Firebase project, IntaSend account or CJ Dropshipping key
  /// required. Flip to false once real credentials are wired up in
  /// lib/data/services and InitialBinding. See README.md.
  static const bool useMockData = true;

  /// The platform's cut of an order subtotal — 2%, applied to product
  /// subtotal only (never shipping/tax unless explicitly configured).
  /// The authoritative computation happens server-side in
  /// functions/src/orders.ts; this constant is for client-side display
  /// estimates (e.g. showing a seller their expected payout) and must be
  /// kept in sync with the server's rate by hand until plan/fee config
  /// moves to Firestore-backed admin settings.
  static const double platformServiceFeeRate = 0.02;
}

/// Backend endpoints. In production these point at Firebase Cloud
/// Functions (see /functions) that hold the real CJ Dropshipping and
/// IntaSend secret keys — the Flutter app never talks to those APIs
/// directly, so a decompiled app never leaks a secret key.
class ApiEndpoints {
  ApiEndpoints._();

  static const String baseFunctionsUrl =
      'https://us-central1-sellora-20.cloudfunctions.net';

  static const String cjSearchProducts = '$baseFunctionsUrl/cjSearchProducts';
  static const String cjProductDetail = '$baseFunctionsUrl/cjProductDetail';
  static const String cjCreateOrder = '$baseFunctionsUrl/cjCreateOrder';
  static const String cjTrackShipment = '$baseFunctionsUrl/cjTrackShipment';

  /// Re-prices and writes the order server-side — see
  /// functions/src/orders.ts. The client never writes an order document
  /// directly; firestore.rules denies it (`orders` create is `if false`).
  static const String createOrder = '$baseFunctionsUrl/createOrder';

  static const String intasendCollectMpesa =
      '$baseFunctionsUrl/intasendCollectMpesa';
  static const String intasendCheckout = '$baseFunctionsUrl/intasendCheckout';
  static const String intasendStatus = '$baseFunctionsUrl/intasendStatus';
}
