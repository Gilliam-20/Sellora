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

  /// Tenant-owned listings, keyed `(store_id, id)`. RLS scopes writes to
  /// the owning seller.
  SupabaseQueryBuilder get products => client.from('products');

  /// One table for every store's orders; RLS limits reads to the buyer,
  /// the seller, and admin.
  SupabaseQueryBuilder get orders => client.from('orders');

  SupabaseQueryBuilder get notifications => client.from('notifications');
  SupabaseQueryBuilder get plans => client.from('subscription_plans');
  SupabaseQueryBuilder get billingHistory => client.from('billing_history');
  SupabaseQueryBuilder get subscriptions => client.from('subscriptions');

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
