/// Supabase project connection. Both values are public by design, like the
/// Firebase web config they replace: the key only grants what the RLS
/// policies in `supabase/migrations/` allow. The secret/service-role key
/// must never appear anywhere in this app.
///
/// Override per environment with
/// `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...`.
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ktpxbrtjmqdsnlmfslbq.supabase.co',
  );

  /// The project's publishable key (`sb_publishable_...`) or its legacy
  /// `anon` JWT — Supabase.initialize accepts either.
  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_8Z9dvxJJFahQTT45WW3vkA_YUYkwO-9',
  );
}
