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
  /// This constant is for client-side display estimates (e.g. showing a
  /// seller their expected payout) and must be kept in sync with the
  /// server's rate by hand until plan/fee config moves to Firestore-backed
  /// admin settings. NOTE: the single-vendor `functions/index.js` this app
  /// currently deploys against (adopted 2026-09-12, see WORKLOG.md) has no
  /// seller/store concept and computes no platform fee at all — this rate
  /// isn't actually applied anywhere server-side right now.
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

  /// Public, unauthenticated CJ catalog browse/search/detail — see
  /// functions/index.js's `searchProducts`/`getProductDetail`/
  /// `getCategories`. Every response is wrapped `{success, data, message}`.
  static const String searchProducts = '$baseFunctionsUrl/searchProducts';
  static const String getProductDetail = '$baseFunctionsUrl/getProductDetail';
  static const String getCategories = '$baseFunctionsUrl/getCategories';

  /// Shipping-cost estimate only (display, never trusted for checkout
  /// totals) — requires a signed-in caller. functions/index.js's
  /// `calculateFreight`.
  static const String calculateFreight = '$baseFunctionsUrl/calculateFreight';

  /// Admin-only (Firebase Auth custom claim `admin: true`, not the
  /// Firestore `role` field). Runs the full CJ catalog/category sync
  /// pipeline server-side and can take several minutes — see
  /// functions/index.js's `runCatalogSync` and functions/lib/catalogSync.js.
  static const String runCatalogSync = '$baseFunctionsUrl/runCatalogSync';

  /// Re-prices and writes the order server-side — functions/index.js's
  /// `createOrder` (functions/lib/orders.js). The client never writes an
  /// order document directly; firestore.rules denies it (`orders` create
  /// is `if false`). NOTE: this is the single-vendor backend's own
  /// `createOrder` (items keyed by CJ's own `pid`/`vid`, no seller/store/fee
  /// concept at all) — `FirebaseOrderRepository.placeOrder` still sends/reads
  /// the *old*, deleted TS backend's shape (`productId`, `orderId`/`code`/
  /// `serviceFeeAmount` in the response) and has no real CJ `vid` to send in
  /// the first place: `ProductVariant` is only `{name, options}` strings, not
  /// a purchasable per-SKU id (see SELLORA_IMPLEMENTATION_PLAN.md's PHASE 4).
  /// Not reconciled by this pass — genuinely blocked on that variant-id gap,
  /// not just unstarted work.
  static const String createOrder = '$baseFunctionsUrl/createOrder';

  /// Order-checkout payment (not billing) — functions/index.js's
  /// `payOrderMpesa`/`payOrderCard`/`confirmIntasendPayment`. Each acts on
  /// an already-created order (by id), not a client-supplied amount — see
  /// IntasendService. NOTE: `FirebaseOrderRepository.placeOrder`'s own
  /// request/response shape is still unreconciled with `createOrder`
  /// (flagged above) — these three endpoints are correctly named/shaped now,
  /// but a real order id to call them with still doesn't exist end-to-end.
  static const String payOrderMpesa = '$baseFunctionsUrl/payOrderMpesa';
  static const String payOrderCard = '$baseFunctionsUrl/payOrderCard';
  static const String confirmIntasendPayment =
      '$baseFunctionsUrl/confirmIntasendPayment';

  /// Creates a pending billing_history entry for a seller's subscription
  /// purchase, server-priced from subscription_plans — see
  /// functions/lib/subscriptions.js. Activation only happens on confirmed
  /// payment (confirmBillingPayment or the IntaSend webhook), never here.
  static const String subscribeSeller = '$baseFunctionsUrl/subscribeSeller';
  static const String payBillingMpesa = '$baseFunctionsUrl/payBillingMpesa';
  static const String payBillingCard = '$baseFunctionsUrl/payBillingCard';
  static const String confirmBillingPayment =
      '$baseFunctionsUrl/confirmBillingPayment';
}
