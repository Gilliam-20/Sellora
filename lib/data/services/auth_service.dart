import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/auth_link_error.dart';

/// Thin wrapper over Supabase Auth. Kept deliberately dumb — it only
/// knows about authentication, never about `profiles` rows or roles.
/// AuthRepository composes this with SupabaseService to build the full
/// [UserModel].
class AuthService extends GetxService {
  GoTrueClient get _auth => Supabase.instance.client.auth;

  User? get currentUser => _auth.currentUser;
  Session? get currentSession => _auth.currentSession;
  Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;

  StreamSubscription<AuthState>? _recoverySub;
  bool _isRecoveringPassword = false;
  final _linkErrors = StreamController<AuthLinkError>.broadcast();
  AuthLinkError? _unheardLinkError;

  /// Where auth email links (password reset, sign-up confirmation) send the
  /// user back to. On web, the page that asked, so a dev server gets its
  /// own links back. On Android, the app itself: the `sellora://` scheme
  /// is registered in AndroidManifest.xml, and a PKCE link has to come back
  /// to the device holding its code verifier. Both must be in the
  /// project's redirect allow-list (Authentication → URL Configuration),
  /// or Supabase falls back to the Site URL.
  static String get authRedirectUrl =>
      kIsWeb ? '${Uri.base.origin}${Uri.base.path}' : mobileAuthRedirectUrl;

  static const mobileAuthRedirectUrl = 'sellora://auth-callback';

  /// Each auth email link that opens the app but can't be used — expired,
  /// already used, or opened on another device. See [AuthLinkError].
  Stream<AuthLinkError> get linkErrors => _linkErrors.stream;

  /// A link error that arrived before anything listened to [linkErrors] —
  /// on a cold start the launch link is handled while the app is still
  /// starting up. Returns it once, then null.
  AuthLinkError? takeUnheardLinkError() {
    final error = _unheardLinkError;
    _unheardLinkError = null;
    return error;
  }

  /// True from the moment a password-recovery link opens the app until the
  /// new password is saved or the session changes hands. The recovery link
  /// (a reset email, or grant-admin.js's first-login link) is consumed by
  /// `Supabase.initialize()` before runApp, so this is usually already true
  /// by the time any screen asks.
  bool get isRecoveringPassword => _isRecoveringPassword;

  /// Emits each time a recovery link opens the app. [authStateChanges]
  /// replays its latest event to a new listener, so one subscribed after
  /// startup still hears about the link the app was launched with.
  Stream<void> get passwordRecoveries => authStateChanges
      .where((s) => s.event == AuthChangeEvent.passwordRecovery);

  @override
  void onInit() {
    super.onInit();
    _recoverySub = authStateChanges.listen(
      (state) {
        switch (state.event) {
          case AuthChangeEvent.passwordRecovery:
            _isRecoveringPassword = true;
          case AuthChangeEvent.signedIn:
          case AuthChangeEvent.signedOut:
          case AuthChangeEvent.userUpdated:
            _isRecoveringPassword = false;
          default:
            break;
        }
      },
      // A failed link (expired, already used) arrives as a stream error.
      // There's no session to track, but the user needs telling; any other
      // error here (a refresh failing offline) is already handled by
      // supabase_flutter's own retry.
      onError: (Object error) {
        final linkError = AuthLinkError.fromException(error);
        if (linkError == null) return;
        if (_linkErrors.hasListener) {
          _linkErrors.add(linkError);
        } else {
          _unheardLinkError = linkError;
        }
      },
    );
  }

  @override
  void onClose() {
    _recoverySub?.cancel();
    _linkErrors.close();
    super.onClose();
  }

  /// [metadata] becomes `raw_user_meta_data`, which the `handle_new_user`
  /// trigger reads to create the profile (and a seller's store) in the same
  /// transaction as the account.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required Map<String, dynamic> metadata,
  }) {
    return _auth.signUp(
      email: email,
      password: password,
      data: metadata,
      emailRedirectTo: authRedirectUrl,
    );
  }

  Future<AuthResponse> signIn(
      {required String email, required String password}) {
    return _auth.signInWithPassword(email: email, password: password);
  }

  /// Re-issues the access token, picking up any `app_metadata` change
  /// (such as an admin grant or revocation) made since the last refresh.
  Future<AuthResponse> refreshSession() => _auth.refreshSession();

  /// Re-reads the account from the server rather than the cached session.
  Future<UserResponse> reloadUser() => _auth.getUser();

  Future<void> resendVerification(String email) => _auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: authRedirectUrl,
      );

  /// The link returns to [authRedirectUrl].
  Future<void> sendPasswordReset(String email) =>
      _auth.resetPasswordForEmail(email, redirectTo: authRedirectUrl);

  /// Sets a new password on the signed-in (typically recovery) session.
  Future<UserResponse> updatePassword(String password) =>
      _auth.updateUser(UserAttributes(password: password));

  Future<void> signOut() => _auth.signOut();
}
