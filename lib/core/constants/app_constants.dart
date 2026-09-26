import '../config/supabase_config.dart';

class AppConstants {
  AppConstants._();

  static const String appName = 'Sellora';

  /// The platform's cut of an order subtotal — 2%, applied to product
  /// subtotal only (never shipping/tax unless explicitly configured).
  /// Client-side display estimates only (e.g. showing a seller their
  /// expected payout). The rate actually charged is `SERVICE_FEE_RATE` in
  /// supabase/functions/_shared/orders.js, snapshotted onto each order at
  /// creation — keep the two in step by hand.
  static const double platformServiceFeeRate = 0.02;
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
  /// `{pid, vid, quantity}` with CJ's own ids; `storeId` is required.
  /// Still unreconciled: `shippingAddress.line` is one free-text string, not
  /// the `{fullName, phone, email, line1, line2, city, province, zip}` shape
  /// CJ fulfilment needs (see SELLORA_IMPLEMENTATION_PLAN.md's PHASE 8).
  static const String createOrder = '$baseFunctionsUrl/createOrder';

  /// Order-checkout payment (not billing). Each acts on an already-created
  /// order (by id), never a client-supplied amount — see IntasendService.
  static const String payOrderMpesa = '$baseFunctionsUrl/payOrderMpesa';
  static const String payOrderCard = '$baseFunctionsUrl/payOrderCard';
  static const String confirmIntasendPayment =
      '$baseFunctionsUrl/confirmIntasendPayment';

  /// Creates a pending billing_history entry for a seller's subscription
  /// purchase, server-priced from subscription_plans
  /// (supabase/functions/_shared/subscriptions.js). Activation only happens
  /// on confirmed payment (confirmBillingPayment or the IntaSend webhook).
  static const String subscribeSeller = '$baseFunctionsUrl/subscribeSeller';
  static const String payBillingMpesa = '$baseFunctionsUrl/payBillingMpesa';
  static const String payBillingCard = '$baseFunctionsUrl/payBillingCard';
  static const String confirmBillingPayment =
      '$baseFunctionsUrl/confirmBillingPayment';
}
