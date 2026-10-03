import '../config/supabase_config.dart';

class AppConstants {
  AppConstants._();

  static const String appName = 'Sellora';

  /// The platform's default cut of an order subtotal — 7%, applied to
  /// product subtotal only (never shipping/tax unless explicitly
  /// configured). An admin can change the live rate (Admin → Plans), which
  /// screens read through [FeeRepository]; this is the fallback until that
  /// answers, and what the signed-out marketing page quotes. The rate
  /// actually charged is read by supabase/functions/_shared/fees.js and
  /// snapshotted onto each order at creation. Keep this in step with
  /// `DEFAULT_SERVICE_FEE_RATE` there and `service_fee_settings()`.
  static const double platformServiceFeeRate = 0.07;

  /// Where the web build is hosted, for links shared from a non-web build
  /// (on web the page's own origin is used). Override with
  /// `--dart-define=SELLORA_WEB_URL=https://...`.
  static const String webAppUrl = String.fromEnvironment('SELLORA_WEB_URL',
      defaultValue: 'https://sellora.app');

  /// Which build an error report came from. Set it per deploy with
  /// `--dart-define=SELLORA_RELEASE=<git sha or version>` (docs/RUNBOOK.md).
  static const String release =
      String.fromEnvironment('SELLORA_RELEASE', defaultValue: 'unversioned');
}

/// Backend endpoints: routes of Sellora's own `api` Supabase Edge Function
/// (supabase/functions/api/index.ts), which holds the real CJ Dropshipping
/// and IntaSend secret keys — the Flutter app never talks to those APIs
/// directly, so a decompiled app never leaks a secret key. Every response
/// is wrapped `{success, data}` / `{success: false, message}`.
class ApiEndpoints {
  ApiEndpoints._();

  static const String baseFunctionsUrl =
      '${SupabaseConfig.url}/functions/v1/api';

  /// Public, unauthenticated CJ catalog browse/search/detail (GET).
  static const String searchProducts = '$baseFunctionsUrl/searchProducts';
  static const String getProductDetail = '$baseFunctionsUrl/getProductDetail';
  static const String getCategories = '$baseFunctionsUrl/getCategories';

  /// Shipping-cost estimate only (display, never trusted for checkout
  /// totals) — requires a signed-in caller.
  static const String calculateFreight = '$baseFunctionsUrl/calculateFreight';

  /// Admin-only (`app_metadata.role = 'admin'`, set by
  /// supabase/scripts/grant-admin.js — not the `profiles.role` column). Runs
  /// the CJ catalog/category sync into `catalog_products` server-side
  /// (supabase/functions/_shared/catalogSync.js); it can take a while.
  static const String runCatalogSync = '$baseFunctionsUrl/runCatalogSync';

  /// Re-prices and writes the order server-side
  /// (supabase/functions/_shared/orders.js). The client never writes an
  /// order row directly — `orders` has no insert policy. Items are
  /// `{pid, vid, quantity}` with CJ's own ids; `storeId` is required, and
  /// so are the address fields CJ ships to (see ShippingAddress).
  static const String createOrder = '$baseFunctionsUrl/createOrder';

  /// Order-checkout payment (not billing). Each acts on an already-created
  /// order (by id), never a client-supplied amount — see IntasendService.
  static const String payOrderMpesa = '$baseFunctionsUrl/payOrderMpesa';
  static const String payOrderCard = '$baseFunctionsUrl/payOrderCard';
  static const String confirmIntasendPayment =
      '$baseFunctionsUrl/confirmIntasendPayment';

  /// Admin-only. Refunds an order through the provider that took the
  /// payment (supabase/functions/_shared/refunds.js); body
  /// `{orderId, amount?, reason?, comment?}`, where omitting `amount`
  /// refunds whatever is left. A refusal comes back as 409 (order state) or
  /// 400 (amount) with a message meant for the admin.
  static const String refundOrder = '$baseFunctionsUrl/refundOrder';

  /// Creates a pending billing_history entry for a seller's subscription
  /// purchase, server-priced from subscription_plans
  /// (supabase/functions/_shared/subscriptions.js). Activation only happens
  /// on confirmed payment (confirmBillingPayment or the IntaSend webhook).
  static const String subscribeSeller = '$baseFunctionsUrl/subscribeSeller';
  static const String payBillingMpesa = '$baseFunctionsUrl/payBillingMpesa';
  static const String payBillingCard = '$baseFunctionsUrl/payBillingCard';
  static const String confirmBillingPayment =
      '$baseFunctionsUrl/confirmBillingPayment';

  /// Deletes the signed-in account: personal data scrubbed, orders kept as
  /// financial records, Auth user soft-deleted. Refused (409) while a paid
  /// order is still being delivered.
  static const String deleteAccount = '$baseFunctionsUrl/deleteAccount';
}
