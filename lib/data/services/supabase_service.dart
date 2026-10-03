import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper around the Supabase client's table builders so repositories
/// don't sprinkle raw table-name strings everywhere. Schema and RLS live in
/// `supabase/migrations/`.
class SupabaseService extends GetxService {
  SupabaseClient get client => Supabase.instance.client;

  SupabaseQueryBuilder get profiles => client.from('profiles');
  SupabaseQueryBuilder get stores => client.from('stores');

  /// A store's buyers — its own table (not a column read off `profiles`) so
  /// a seller can be granted their own store's customers without any read
  /// on `profiles`.
  SupabaseQueryBuilder get storeCustomers => client.from('store_customers');

  /// Tenant-owned listings, keyed `(store_id, id)`. RLS limits reads and
  /// writes to the owning seller (and admin reads) — it carries their cost
  /// price, i.e. their margin.
  SupabaseQueryBuilder get products => client.from('products');

  /// What buyers read: listed products of sellers in good standing, with
  /// `cost_price` and each variant's `costPrice` left out. Read-only.
  SupabaseQueryBuilder get storefrontProducts =>
      client.from('storefront_products');

  /// Each store's design: the owner's draft and the published copy.
  SupabaseQueryBuilder get storeDesigns => client.from('store_designs');

  /// Published designs of open storefronts; what buyers read. Read-only.
  SupabaseQueryBuilder get storefrontDesigns =>
      client.from('storefront_designs');

  /// Emails collected by a storefront's newsletter section; owner reads.
  SupabaseQueryBuilder get newsletterSubscribers =>
      client.from('newsletter_subscribers');

  /// One table for every store's orders; RLS limits reads to the buyer,
  /// the seller, and admin.
  SupabaseQueryBuilder get orders => client.from('orders');

  /// The seller's (and admin's) read of `orders`: the same rows, plus
  /// `seller_revenue`, which buyers can't read. Read-only.
  SupabaseQueryBuilder get sellerOrders => client.from('seller_orders');

  /// Internal notes on an order: its seller's and admin's, never the
  /// buyer's. Append-only; read alongside the rest of the order's history
  /// through the `order_timeline` function.
  SupabaseQueryBuilder get orderNotes => client.from('order_notes');

  /// Platform settings (pricing, catalog sources, the service fee); admin
  /// only. Sellers read the fee through `service_fee_settings()`.
  SupabaseQueryBuilder get appConfig => client.from('app_config');

  /// Admin-only, read-only: an order's charged amount and refund state,
  /// which are server-only `orders` columns.
  SupabaseQueryBuilder get adminOrderRefunds =>
      client.from('admin_order_refunds');

  /// A store's discount codes; owner and admin only. Buyers test a code
  /// through the `storefront_discount` function instead.
  SupabaseQueryBuilder get discounts => client.from('discounts');

  SupabaseQueryBuilder get notifications => client.from('notifications');

  /// Append-only record of who changed what; admin reads only.
  SupabaseQueryBuilder get auditLogs => client.from('audit_logs');

  /// Uncaught app errors; admin reads only. Written through the
  /// `report_client_error` function, never directly.
  SupabaseQueryBuilder get clientErrors => client.from('client_errors');
  SupabaseQueryBuilder get plans => client.from('subscription_plans');
  SupabaseQueryBuilder get billingHistory => client.from('billing_history');
  SupabaseQueryBuilder get subscriptions => client.from('subscriptions');

  /// A seller's saved payment method and invoice details; owner-written.
  SupabaseQueryBuilder get billingProfiles =>
      client.from('seller_billing_profiles');

  /// The single-row USD-base rate table, refreshed server-side and publicly
  /// readable.
  SupabaseQueryBuilder get fxRates => client.from('fx_rates');

  /// Public bucket for store branding images, one folder per store id.
  StorageFileApi get storeMedia => client.storage.from('store-media');
}

// ---- Model <-> row translation ------------------------------------------
//
// Models keep their camelCase fromMap/toMap keys (shared with the mocks and
// the Edge Function's JSON); Postgres columns are snake_case. Only the top
// level is translated — jsonb columns (items, variants, ...) keep their
// camelCase keys untouched.
//
// Timestamps are translated too. `DateTime.toIso8601String()` on a local
// DateTime carries no offset, which Postgres would read as UTC, silently
// shifting the time by the device's offset. So offset-less timestamps are
// sent as UTC. Postgres returns `...+00:00`, so those come back as local
// ISO strings, and the models' `DateTime.tryParse` sees the same local
// times Firestore used to give them.

final _upper = RegExp(r'[A-Z]');
final _underscored = RegExp(r'_([a-z0-9])');
final _localIso = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?$');
final _postgresIso =
    RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?\+00:00$');

String _snake(String key) =>
    key.replaceAllMapped(_upper, (m) => '_${m[0]!.toLowerCase()}');

String _camel(String column) =>
    column.replaceAllMapped(_underscored, (m) => m[1]!.toUpperCase());

/// A model's `toMap()` as a row. [omit] drops keys (by their model name)
/// the database owns, such as a generated `id` or immutable columns on an
/// update.
Map<String, dynamic> toRow(Map<String, dynamic> map,
    {Set<String> omit = const {}}) {
  return {
    for (final entry in map.entries)
      if (!omit.contains(entry.key))
        _snake(entry.key): entry.value is String &&
                _localIso.hasMatch(entry.value as String)
            ? DateTime.parse(entry.value as String).toUtc().toIso8601String()
            : entry.value,
  };
}

/// A row as the map a model's `fromMap()` expects.
Map<String, dynamic> fromRow(Map<String, dynamic> row) {
  return {
    for (final entry in row.entries)
      _camel(entry.key): entry.value is String &&
              _postgresIso.hasMatch(entry.value as String)
          ? DateTime.parse(entry.value as String).toLocal().toIso8601String()
          : entry.value,
  };
}
