import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:firebase_auth/firebase_auth.dart'
    show FirebaseAuthException, User;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:get/get.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import 'store_repository.dart';

/// Provider-neutral auth failure, so controllers map error codes without
/// importing firebase_auth. [code] is a Firebase Auth/Firestore error code
/// (`invalid-credential`, `permission-denied`, ...) or one of Sellora's own:
/// `profile-missing` (an Auth account with no `users` doc) and
/// `admin-claim-missing` (a `role: admin` doc without the server-granted
/// `admin` custom claim — see functions/scripts/grant-admin.js).
class AuthFailure implements Exception {
  const AuthFailure(this.code);
  final String code;

  @override
  String toString() => 'AuthFailure($code)';
}

/// Firebase Auth treats emails case-insensitively but a stored `email`
/// field doesn't, so every email is stored and sent in one canonical form.
String normalizeEmail(String email) => email.trim().toLowerCase();

abstract class AuthRepository {
  Stream<UserModel?> get userChanges;
  UserModel? get cachedUser;

  /// [storeId] is only meaningful for a store-scoped buyer sign-in (see
  /// AuthController.signInToStore) — MockAuthRepository uses it to attach a
  /// store to a freshly-minted mock buyer; FirebaseAuthRepository ignores it,
  /// since a real buyer's Firestore doc already carries their true storeId.
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

  /// Re-fetches the signed-in account from the identity provider and
  /// reports whether its email address has been verified. Verification is
  /// surfaced during onboarding but not yet required for any action.
  Future<bool> checkEmailVerified();

  /// Re-sends the verification email to the signed-in account.
  Future<void> resendVerificationEmail();

  Future<void> signOut();
  Future<void> updateUser(UserModel user);

  /// Re-reads the signed-in user's Firestore doc, bypassing [cachedUser],
  /// and updates the cache. Needed because subscription activation is now
  /// written by the IntaSend webhook, which the client has no realtime
  /// channel to — see `RoleMiddleware` and the seller onboarding/
  /// subscription controllers' "refresh status" actions.
  Future<UserModel?> refreshCurrentUser();
}

/// Firebase-backed implementation. Composes [AuthService] (identity)
/// with [FirestoreService] (the `users` document holding role, store
/// name, subscription state, etc).
///
/// There is no admin sign-up path: the admin is one dedicated email,
/// provisioned server-side by functions/scripts/grant-admin.js, which sets
/// the `admin` custom claim and the `role: admin` profile together.
/// firestore.rules refuses a self-created `role: admin` doc, and
/// [_loadProfile] refuses an admin doc that lacks the claim.
class FirebaseAuthRepository extends GetxService implements AuthRepository {
  FirebaseAuthRepository({StoreRepository? storeRepository})
      : _storeRepository = storeRepository ?? Get.find<StoreRepository>();

  final AuthService _auth = Get.find<AuthService>();
  final FirestoreService _fs = Get.find<FirestoreService>();
  final StoreRepository _storeRepository;

  UserModel? _cached;

  @override
  UserModel? get cachedUser => _cached;

  @override
  Stream<UserModel?> get userChanges async* {
    await for (final fbUser in _auth.authStateChanges) {
      if (fbUser == null) {
        _cached = null;
        yield null;
        continue;
      }
      try {
        _cached = await _loadProfile(fbUser);
      } catch (e) {
        // A resumed session that no longer resolves to a usable profile
        // (e.g. an admin whose claim was revoked) is treated as signed out.
        debugPrint('FirebaseAuthRepository.userChanges: $e');
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
      final cred =
          await _auth.signIn(email: normalizeEmail(email), password: password);
      final UserModel? user;
      try {
        // Force a token refresh so a claim granted or revoked since this
        // device last signed in takes effect now, not up to an hour later.
        user = await _loadProfile(cred.user!, forceTokenRefresh: true);
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
    return _guard(() async {
      final canonicalEmail = normalizeEmail(email);
      final cred =
          await _auth.signUp(email: canonicalEmail, password: password);
      final user = await _deleteAuthUserOnFailure(cred.user!, () async {
        final user = UserModel(
          uid: cred.user!.uid,
          name: name.trim(),
          email: canonicalEmail,
          role: UserRole.buyer,
          storeId: storeId,
          createdAt: DateTime.now(),
        );
        // Global identity doc (role bootstrap, same as every other role) plus
        // a mirror under the store's own tenant tree, so Firestore rules can
        // authorize store-scoped reads without ever touching `users`.
        await _fs.users.doc(user.uid).set(user.toMap());
        await _fs.storeCustomers(storeId).doc(user.uid).set(user.toMap());
        return user;
      });
      await _sendVerification(cred.user!);
      _cached = user;
      return user;
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
    return _guard(() async {
      final canonicalEmail = normalizeEmail(email);
      final cred =
          await _auth.signUp(email: canonicalEmail, password: password);
      final user = await _deleteAuthUserOnFailure(cred.user!, () async {
        final user = UserModel(
          uid: cred.user!.uid,
          name: name.trim(),
          email: canonicalEmail,
          phone: phone.trim(),
          role: UserRole.seller,
          storeName: storeName.trim(),
          sellerStatus: SellerStatus.pendingApproval,
          sellerTermsAcceptedAt: DateTime.now(),
          sellerTermsVersion: sellerTermsVersion,
          createdAt: DateTime.now(),
        );
        await _fs.users.doc(user.uid).set(user.toMap());
        await createStoreForSeller(_storeRepository,
            sellerId: user.uid, storeName: user.storeName!);
        return user;
      });
      await _sendVerification(cred.user!);
      _cached = user;
      return user;
    });
  }

  /// Reads the `users` doc and reconciles it with the ID token's claims.
  /// Admin access is decided by the `admin` custom claim, which only the
  /// Admin SDK can set — never by the Firestore `role` field alone, which
  /// firestore.rules' isAdmin() doesn't trust either. Returns null only
  /// when the profile doc doesn't exist (yet: a sign-up in progress fires
  /// authStateChanges before its doc is written).
  Future<UserModel?> _loadProfile(User fbUser,
      {bool forceTokenRefresh = false}) async {
    final doc = await _fs.users.doc(fbUser.uid).get();
    if (!doc.exists) return null;
    final user = UserModel.fromMap(doc.data()!);
    if (user.role == UserRole.admin) {
      final token = await fbUser.getIdTokenResult(forceTokenRefresh);
      if (token.claims?['admin'] != true) {
        throw const AuthFailure('admin-claim-missing');
      }
    }
    return user;
  }

  /// Translates provider exceptions into [AuthFailure] so the controller
  /// never has to string-match `toString()` output.
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(e.code);
    } on FirebaseException catch (e) {
      throw AuthFailure(e.code);
    }
  }

  /// Best effort — a failed verification email must never fail sign-up.
  Future<void> _sendVerification(User fbUser) async {
    try {
      await fbUser.sendEmailVerification();
    } catch (e) {
      debugPrint('FirebaseAuthRepository: verification email failed: $e');
    }
  }

  /// The Auth account is created before its Firestore profile, so a failed
  /// profile write would otherwise strand an email that can neither sign in
  /// (no profile) nor re-register (email-already-in-use).
  Future<UserModel> _deleteAuthUserOnFailure(
      User fbUser, Future<UserModel> Function() writeProfile) async {
    try {
      return await writeProfile();
    } catch (_) {
      try {
        await fbUser.delete();
      } catch (_) {
        await _auth.signOut();
      }
      rethrow;
    }
  }

  @override
  Future<bool> checkEmailVerified() async {
    final fbUser = _auth.currentUser;
    if (fbUser == null) return false;
    try {
      await fbUser.reload();
    } catch (e) {
      // Offline: fall back to the last known state rather than failing.
      debugPrint('FirebaseAuthRepository.checkEmailVerified: $e');
    }
    return _auth.currentUser?.emailVerified ?? false;
  }

  @override
  Future<void> resendVerificationEmail() => _guard(() async {
        final fbUser = _auth.currentUser;
        if (fbUser != null) await fbUser.sendEmailVerification();
      });

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordReset(normalizeEmail(email)));

  @override
  Future<void> signOut() async {
    _cached = null;
    await _auth.signOut();
  }

  @override
  Future<void> updateUser(UserModel user) async {
    await _fs.users.doc(user.uid).update(user.toMap());
    _cached = user;
  }

  @override
  Future<UserModel?> refreshCurrentUser() async {
    final fbUser = _auth.currentUser;
    if (_cached == null || fbUser == null) return null;
    _cached = await _guard(() => _loadProfile(fbUser, forceTokenRefresh: true));
    return _cached;
  }
}
