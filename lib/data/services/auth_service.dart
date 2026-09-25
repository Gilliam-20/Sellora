import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper over Supabase Auth. Kept deliberately dumb — it only
/// knows about authentication, never about `profiles` rows or roles.
/// AuthRepository composes this with SupabaseService to build the full
/// [UserModel].
class AuthService extends GetxService {
  GoTrueClient get _auth => Supabase.instance.client.auth;

  User? get currentUser => _auth.currentUser;
  Session? get currentSession => _auth.currentSession;
  Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;

  /// [metadata] becomes `raw_user_meta_data`, which the `handle_new_user`
  /// trigger reads to create the profile (and a seller's store) in the same
  /// transaction as the account.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required Map<String, dynamic> metadata,
  }) {
    return _auth.signUp(email: email, password: password, data: metadata);
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

  Future<void> resendVerification(String email) =>
      _auth.resend(type: OtpType.signup, email: email);

  Future<void> sendPasswordReset(String email) =>
      _auth.resetPasswordForEmail(email);

  Future<void> signOut() => _auth.signOut();
}
