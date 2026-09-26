import 'package:supabase_flutter/supabase_flutter.dart';

/// Why an auth email link (password reset, sign-up confirmation) couldn't
/// be used. Supabase redirects a bad link back to the app with
/// `error`/`error_code`/`error_description` in the query or fragment, and
/// supabase_flutter re-raises the same values as an [AuthException] on the
/// auth stream — this reads either shape into one thing the app can show.
class AuthLinkError {
  const AuthLinkError({this.code, this.description});

  /// Supabase's `error_code`, e.g. `otp_expired` or `flow_state_not_found`.
  final String? code;

  /// Supabase's own `error_description` — logged, never shown as-is.
  final String? description;

  /// The error the app was launched with (web only), captured in main()
  /// before the URL is cleaned, for the screen to read once it opens.
  static AuthLinkError? atLaunch;

  /// The link error in [uri], or null when it carries none.
  static AuthLinkError? fromUri(Uri uri) {
    final params = <String, String>{...uri.queryParameters};
    // An error arrives in the fragment (`#error=...`) for implicit-flow
    // links. A fragment that's a hash-routing path isn't one of those.
    if (uri.fragment.contains('=') && !uri.fragment.startsWith('/')) {
      try {
        params.addAll(Uri.splitQueryString(uri.fragment));
      } on FormatException {
        // Not a query string after all; nothing to read.
      }
    }
    final code = params['error_code'];
    final error = params['error'];
    final description = params['error_description'];
    if (code == null && error == null && description == null) return null;
    return AuthLinkError(code: code ?? error, description: description);
  }

  /// The link error behind [error], or null when it's some other auth
  /// failure (a network error during token refresh, say) that has nothing
  /// to do with a link.
  static AuthLinkError? fromException(Object error) {
    if (error is! AuthException) return null;
    // getSessionFromUrl puts the URL's error_code in statusCode; an HTTP
    // failure's statusCode is numeric instead.
    final statusCode = error.statusCode;
    if (statusCode != null && int.tryParse(statusCode) == null) {
      return AuthLinkError(code: statusCode, description: error.message);
    }
    // A PKCE link opened somewhere other than where it was requested: the
    // code verifier lives on the requesting device.
    if (error.message.contains('Code verifier')) {
      return AuthLinkError(
          code: 'flow_state_not_found', description: error.message);
    }
    return null;
  }

  /// Whether the link was opened on a different device or browser from the
  /// one that asked for it — a different fix from an expired link.
  bool get isWrongDevice =>
      code == 'flow_state_not_found' ||
      code == 'flow_state_expired' ||
      code == 'bad_code_verifier';

  String get title => isWrongDevice
      ? 'Open this link where you requested it'
      : 'This link has expired';

  String get message => isWrongDevice
      ? 'For your security, email links only work on the device and browser '
          'that asked for them. Open it there, or request a new one from '
          'this device.'
      : 'Email links work once, for a limited time. To get a fresh one, use '
          '"Forgot password?" on the page where you sign in, or sign in to '
          'resend your confirmation email.';
}
