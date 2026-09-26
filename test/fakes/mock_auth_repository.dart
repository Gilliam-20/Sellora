import 'dart:async';
import 'package:get/get.dart';
import 'package:sellora/data/models/user_model.dart';
import 'package:sellora/data/repositories/auth_repository.dart';
import 'package:sellora/data/repositories/store_repository.dart';

/// In-memory test stand-in for [SupabaseAuthRepository]. Accepts any
/// email/password and keeps a single fake user in memory.
class MockAuthRepository extends GetxService implements AuthRepository {
  MockAuthRepository({StoreRepository? storeRepository})
      : _storeRepository = storeRepository ?? Get.find<StoreRepository>();

  final StoreRepository _storeRepository;
  final _controller = StreamController<UserModel?>.broadcast();
  UserModel? _current;

  @override
  UserModel? get cachedUser => _current;

  @override
  // The broadcast controller only emits on sign-in/out, so on a cold
  // start (nothing signed in yet) AuthController.checkSession()'s
  // `.first` would hang for its full timeout instead of resolving
  // immediately to "no session" — a several-second stall on every
  // launch of the very demo mode the README promises is instant.
  // Yielding the current value first mirrors how SupabaseAuthRepository
  // behaves against a real authStateChanges stream.
  Stream<UserModel?> get userChanges async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<UserModel> signIn(
      {required String email,
      required String password,
      String? storeId}) async {
    await Future.delayed(const Duration(milliseconds: 600));
    // Demo convenience: an email containing "seller" or "admin" logs in
    // to that portal so reviewers can explore all three without a
    // backend. Any other email signs in as a buyer.
    final role = email.contains('admin')
        ? UserRole.admin
        : email.contains('seller')
            ? UserRole.seller
            : UserRole.buyer;

    // A mock buyer is scoped to whichever store's sign-in page they used
    // (see AuthController.signInToStore) — without this, every mock buyer
    // sign-in used to come back with storeId: null, silently breaking
    // CartRepository.setStore/BuyerOrdersController's store-scoped reads.
    final buyerUid = role == UserRole.buyer && storeId != null
        ? 'mock-buyer-$storeId'
        : 'mock-${role.name}';

    final user = UserModel(
      uid: buyerUid,
      name: role == UserRole.admin
          ? 'Sellora Admin'
          : (role == UserRole.seller ? 'Amina\'s Store' : 'Jane Buyer'),
      email: email,
      role: role,
      storeName: role == UserRole.seller ? "Amina's Curated Picks" : null,
      sellerStatus: role == UserRole.seller ? SellerStatus.active : null,
      subscriptionPlanId: role == UserRole.seller ? 'growth' : null,
      subscriptionActiveUntil: role == UserRole.seller
          ? DateTime.now().add(const Duration(days: 18))
          : null,
      currencyCode: 'KES',
      storeId: role == UserRole.buyer ? storeId : null,
      createdAt: DateTime.now(),
    );
    _current = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<UserModel> signUpBuyer({
    required String name,
    required String email,
    required String password,
    required String storeId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));
    final user = UserModel(
      uid: 'mock-buyer-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      email: email,
      role: UserRole.buyer,
      currencyCode: 'KES',
      storeId: storeId,
      createdAt: DateTime.now(),
    );
    _current = user;
    _controller.add(user);
    return user;
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
    await Future.delayed(const Duration(milliseconds: 600));
    final user = UserModel(
      uid: 'mock-seller-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      email: email,
      phone: phone,
      role: UserRole.seller,
      storeName: storeName,
      sellerStatus: SellerStatus.pendingApproval,
      sellerTermsAcceptedAt: DateTime.now(),
      sellerTermsVersion: sellerTermsVersion,
      currencyCode: 'KES',
      createdAt: DateTime.now(),
    );
    // Mirrors the real sign-up's store creation (the handle_new_user
    // trigger in supabase/migrations). The seeded
    // quick-login accounts already have stores from MockSeedData and never
    // go through this path.
    await createStoreForSeller(_storeRepository,
        sellerId: user.uid, storeName: storeName);
    _current = user;
    _controller.add(user);
    return user;
  }

  /// Mock accounts have no inbox to verify against.
  @override
  Future<bool> checkEmailVerified() async => true;

  @override
  Future<void> resendVerificationEmail() async {}

  @override
  Future<void> sendPasswordReset(String email) async {
    await Future.delayed(const Duration(milliseconds: 400));
  }

  // No emails are sent in mock mode, so no recovery link ever opens the app.
  @override
  Stream<void> get passwordRecoveries => const Stream.empty();

  @override
  bool get isRecoveringPassword => false;

  @override
  Future<UserModel> updatePassword(String newPassword) async {
    final user = _current;
    if (user == null) throw StateError('No signed-in mock user.');
    return user;
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _controller.add(null);
  }

  @override
  Future<void> updateUser(UserModel user) async {
    _current = user;
    _controller.add(user);
  }

  @override
  Future<UserModel?> refreshCurrentUser() async {
    // Mock activation (MockSubscriptionRepository.subscribeSeller) is
    // already synchronous, so there's never anything to re-fetch.
    return _current;
  }
}
