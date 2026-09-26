import 'package:flutter/foundation.dart' show debugPrint;
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show
        AuthChangeEvent,
        AuthException,
        AuthRetryableFetchException,
        PostgrestException,
        User;
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';

/// Provider-neutral auth failure, so controllers map error codes without
/// importing supabase_flutter. [code] uses the names AuthController maps
/// (they began as Firebase Auth's: `invalid-credential`,
/// `permission-denied`, ...; SupabaseAuthRepository translates onto them),
/// or one of Sellora's own: `profile-missing` (an Auth account with no
/// `profiles` row), `admin-claim-missing` (a `role: admin` profile without
/// the server-granted `app_metadata.role` — see
/// supabase/scripts/grant-admin.js) and `email-not-confirmed`.
class AuthFailure implements Exception {
  const AuthFailure(this.code);
  final String code;

  @override
  String toString() => 'AuthFailure($code)';
}

/// Supabase Auth treats emails case-insensitively but a stored `email`
/// column doesn't, so every email is stored and sent in one canonical form.
String normalizeEmail(String email) => email.trim().toLowerCase();

abstract class AuthRepository {
  Stream<UserModel?> get userChanges;
  UserModel? get cachedUser;

  /// [storeId] is only meaningful for a store-scoped buyer sign-in (see
  /// AuthController.signInToStore). SupabaseAuthRepository ignores it,
  /// since a real buyer's profile already carries their true storeId; the
  /// in-memory test fake uses it to attach a store to a new buyer.
  Future<UserModel> signIn(
      {required String email, required String password, String? storeId});

  /// [storeId] is the store (see StoreModel) the buyer is registering as
  /// a customer of — every buyer belongs to exactly one store.
  Future<UserModel> signUpBuyer({
    required String name,
    required String email,
    required String password,
    required String storeId,
  });
  Future<UserModel> signUpSeller({
    required String name,
    required String email,
    required String password,
    required String storeName,
    required String phone,
    required bool hasAcceptedTerms,
  });
  Future<void> sendPasswordReset(String email);

  /// Emits each time a password-recovery link (a reset email, or
  /// supabase/scripts/grant-admin.js's first-login link) opens the app with
  /// a recovery session — including the link the app was launched with,
  /// for a listener that subscribes after startup.
  Stream<void> get passwordRecoveries;

  /// Whether the current session came from a recovery link and is still
  /// waiting for [updatePassword].
  bool get isRecoveringPassword;

  /// Sets a new password on the recovery session's account, then loads and
  /// caches its profile — the user is signed in once this returns.
  Future<UserModel> updatePassword(String newPassword);

  /// Re-fetches the signed-in account from the identity provider and
  /// reports whether its email address has been verified. Verification is
  /// surfaced during onboarding but not yet required for any action.
  Future<bool> checkEmailVerified();

  /// Re-sends the verification email to the signed-in account.
  Future<void> resendVerificationEmail();

  Future<void> signOut();
  Future<void> updateUser(UserModel user);

  /// Re-reads the signed-in user's profile, bypassing [cachedUser], and
  /// updates the cache. Needed because subscription activation is written
  /// by the IntaSend webhook, which the client has no realtime channel to —
  /// see `RoleMiddleware` and the seller onboarding/subscription
  /// controllers' "refresh status" actions.
  Future<UserModel?> refreshCurrentUser();
}

/// Supabase-backed implementation. Composes [AuthService] (identity)
/// with the `profiles` table (role, store name, subscription state, etc).
///
/// Sign-up hands the profile fields to Supabase Auth as user metadata; the
/// `handle_new_user` trigger (supabase/migrations) creates the profile —
/// and a seller's store, or a buyer's store membership — in the same
/// transaction as the account. A failed profile write rolls the account
/// back with it, so there's no half-created account to clean up.
///
/// There is no admin sign-up path: the admin is one dedicated email,
/// provisioned server-side by supabase/scripts/grant-admin.js, which sets
/// `app_metadata.role = 'admin'` (service-role only) and the `role: admin`
/// profile together. The trigger refuses a self-assigned admin role, and
/// [_loadProfile] refuses an admin profile whose session lacks the grant.
class SupabaseAuthRepository extends GetxService implements AuthRepository {
  final AuthService _auth = Get.find<AuthService>();
  final SupabaseService _db = Get.find<SupabaseService>();

  UserModel? _cached;

  @override
  UserModel? get cachedUser => _cached;

  @override
  Stream<UserModel?> get userChanges async* {
    await for (final state in _auth.authStateChanges) {
      // Token refreshes and profile edits also arrive here; only a change
      // of *who* is signed in reloads the profile, which is what the
      // controllers were built against.
      if (state.event != AuthChangeEvent.initialSession &&
          state.event != AuthChangeEvent.signedIn &&
          state.event != AuthChangeEvent.signedOut) {
        continue;
      }
      final user = state.session?.user;
      if (user == null) {
        _cached = null;
        yield null;
        continue;
      }
      try {
        _cached = await _loadProfile(user);
      } catch (e) {
        // A resumed session that no longer resolves to a usable profile
        // (e.g. an admin whose grant was revoked) is treated as signed out.
        debugPrint('SupabaseAuthRepository.userChanges: $e');
        await _auth.signOut();
        _cached = null;
      }
      yield _cached;
    }
  }

  @override
  Future<UserModel> signIn(
      {required String email, required String password, String? storeId}) {
    return _guard(() async {
      final res =
          await _auth.signIn(email: normalizeEmail(email), password: password);
      final UserModel? user;
      try {
        // Refresh so an admin grant or revocation made since this device
        // last signed in takes effect now, not at the next token refresh.
        user = await _loadProfile(res.user!, forceTokenRefresh: true);
      } catch (_) {
        await _auth.signOut();
        rethrow;
      }
      if (user == null) {
        await _auth.signOut();
        throw const AuthFailure('profile-missing');
      }
      _cached = user;
      return user;
    });
  }

  @override
  Future<UserModel> signUpBuyer({
    required String name,
    required String email,
    required String password,
    required String storeId,
  }) {
    return _signUp(email, password, {
      'role': UserRole.buyer.name,
      'name': name.trim(),
      'store_id': storeId,
    });
  }

  @override
  Future<UserModel> signUpSeller({
    required String name,
    required String email,
    required String password,
    required String storeName,
    required String phone,
    required bool hasAcceptedTerms,
  }) async {
    if (!hasAcceptedTerms) {
      throw ArgumentError('Seller terms must be accepted before registration.');
    }
    return _signUp(email, password, {
      'role': UserRole.seller.name,
      'name': name.trim(),
      'phone': phone.trim(),
      'store_name': storeName.trim(),
      'seller_terms_version': sellerTermsVersion,
    });
  }

  Future<UserModel> _signUp(
      String email, String password, Map<String, dynamic> metadata) {
    return _guard(() async {
      final res = await _auth.signUp(
          email: normalizeEmail(email), password: password, metadata: metadata);
      // With "Confirm email" enabled on the Supabase project there's no
      // session until the link is clicked, so the profile can't be read
      // yet. The account and profile do exist; the user signs in once
      // they've confirmed.
      if (res.session == null) throw const AuthFailure('email-not-confirmed');
      final user = await _loadProfile(res.user!);
      if (user == null) throw const AuthFailure('profile-missing');
      _cached = user;
      return user;
    });
  }

  /// Reads the `profiles` row and reconciles it with the session's
  /// `app_metadata`. Admin access is decided by `app_metadata.role`, which
  /// only the service role can set — never by the profile's `role` column
  /// alone, which RLS's is_admin() doesn't trust either. Returns null when
  /// the account has no profile (one created outside the app's sign-up).
  Future<UserModel?> _loadProfile(User user,
      {bool forceTokenRefresh = false}) async {
    final row = await _db.profiles.select().eq('uid', user.id).maybeSingle();
    if (row == null) return null;
    final profile = UserModel.fromMap(fromRow(row));
    if (profile.role == UserRole.admin) {
      final current = forceTokenRefresh
          ? (await _auth.refreshSession()).user ?? user
          : user;
      if (current.appMetadata['role'] != 'admin') {
        throw const AuthFailure('admin-claim-missing');
      }
    }
    return profile;
  }

  /// Translates provider exceptions into [AuthFailure] so the controller
  /// never has to string-match `toString()` output.
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on AuthRetryableFetchException {
      throw const AuthFailure('network-request-failed');
    } on AuthException catch (e) {
      throw AuthFailure(_authCode(e));
    } on PostgrestException catch (e) {
      // 42501 is insufficient_privilege: an RLS or guard-trigger refusal.
      throw AuthFailure(
          e.code == '42501' ? 'permission-denied' : e.code ?? 'unknown');
    }
  }

  static String _authCode(AuthException e) {
    switch (e.code) {
      case 'invalid_credentials':
        return 'invalid-credential';
      case 'user_not_found':
        return 'user-not-found';
      case 'email_exists':
      case 'user_already_exists':
        return 'email-already-in-use';
      case 'weak_password':
        return 'weak-password';
      case 'same_password':
        return 'same-password';
      case 'email_address_invalid':
        return 'invalid-email';
      case 'user_banned':
        return 'user-disabled';
      case 'over_request_rate_limit':
      case 'over_email_send_rate_limit':
        return 'too-many-requests';
      case 'email_provider_disabled':
      case 'signup_disabled':
        return 'operation-not-allowed';
      case 'email_not_confirmed':
        return 'email-not-confirmed';
      default:
        return e.code ?? 'unknown';
    }
  }

  @override
  Future<bool> checkEmailVerified() async {
    final signedIn = _auth.currentUser;
    if (signedIn == null) return false;
    var user = signedIn;
    try {
      user = (await _auth.reloadUser()).user ?? user;
    } catch (e) {
      // Offline: fall back to the last known state rather than failing.
      debugPrint('SupabaseAuthRepository.checkEmailVerified: $e');
    }
    return user.emailConfirmedAt != null;
  }

  @override
  Future<void> resendVerificationEmail() => _guard(() async {
        final email = _auth.currentUser?.email;
        if (email != null) await _auth.resendVerification(email);
      });

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordReset(normalizeEmail(email)));

  @override
  Stream<void> get passwordRecoveries => _auth.passwordRecoveries;

  @override
  bool get isRecoveringPassword => _auth.isRecoveringPassword;

  /// A recovery link arrives as its own `passwordRecovery` event, which
  /// [userChanges] skips, so nothing has loaded the profile yet — this does,
  /// with a token refresh so an admin's grant is read fresh.
  @override
  Future<UserModel> updatePassword(String newPassword) => _guard(() async {
        final res = await _auth.updatePassword(newPassword);
        final user = await _loadProfile(res.user!, forceTokenRefresh: true);
        if (user == null) throw const AuthFailure('profile-missing');
        _cached = user;
        return user;
      });

  @override
  Future<void> signOut() async {
    _cached = null;
    await _auth.signOut();
  }

  /// Sends only the self-editable columns. The rest are server-owned (the
  /// profiles_guard_update trigger refuses changes to them), and
  /// [UserModel.copyWith] doesn't carry `storeId`, so sending the whole
  /// map would try to null a buyer's store.
  @override
  Future<void> updateUser(UserModel user) async {
    final map = user.toMap();
    await _guard(() => _db.profiles
        .update(toRow({
          for (final key in const [
            'name',
            'phone',
            'photoUrl',
            'storeName',
            'currencyCode',
          ])
            key: map[key],
        }))
        .eq('uid', user.uid));
    _cached = user;
  }

  @override
  Future<UserModel?> refreshCurrentUser() async {
    final user = _auth.currentUser;
    if (_cached == null || user == null) return null;
    _cached = await _guard(() => _loadProfile(user, forceTokenRefresh: true));
    return _cached;
  }
}
