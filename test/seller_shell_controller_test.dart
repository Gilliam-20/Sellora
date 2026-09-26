import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sellora/data/models/store_model.dart';
import 'package:sellora/data/models/user_model.dart';
import 'package:sellora/data/repositories/auth_repository.dart';
import 'package:sellora/data/repositories/store_repository.dart';
import 'package:sellora/modules/seller/shell/seller_shell_controller.dart';
import 'package:sellora/modules/storefront/store_scope.dart';

void main() {
  final seller = UserModel(
    uid: 'seller-a',
    name: 'Amina',
    email: 'amina@example.com',
    role: UserRole.seller,
  );
  final store = StoreModel(
    id: 'store-a',
    slug: 'aminas-picks',
    sellerId: 'seller-a',
    name: "Amina's Picks",
  );

  test('onInit resolves the signed-in seller\'s own store into StoreScope',
      () async {
    final scope = StoreScope(repository: _FakeStoreRepository([store]));
    final controller = SellerShellController(
      authRepository: _FakeAuthRepository(seller),
      scope: scope,
    );

    controller.onInit();
    // resolveForSeller is fire-and-forget from onInit; give its Future a
    // turn to complete rather than awaiting onInit itself, matching how
    // GetX controllers actually run this in the app.
    await Future<void>.delayed(Duration.zero);

    expect(scope.current.value?.id, 'store-a');
  });

  test('onInit does not throw when no seller is signed in', () async {
    final scope = StoreScope(repository: _FakeStoreRepository([store]));
    final controller = SellerShellController(
      authRepository: _FakeAuthRepository(null),
      scope: scope,
    );

    expect(controller.onInit, returnsNormally);
    expect(scope.current.value, isNull);
  });
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._user);

  final UserModel? _user;

  @override
  UserModel? get cachedUser => _user;

  @override
  Stream<UserModel?> get userChanges => Stream.value(_user);

  @override
  Future<UserModel> signIn(
          {required String email, required String password, String? storeId}) =>
      throw UnimplementedError();

  @override
  Future<UserModel> signUpBuyer({
    required String name,
    required String email,
    required String password,
    required String storeId,
  }) =>
      throw UnimplementedError();

  @override
  Future<UserModel> signUpSeller({
    required String name,
    required String email,
    required String password,
    required String storeName,
    required String phone,
    required bool hasAcceptedTerms,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> sendPasswordReset(String email) => throw UnimplementedError();

  @override
  Stream<void> get passwordRecoveries => throw UnimplementedError();

  @override
  bool get isRecoveringPassword => throw UnimplementedError();

  @override
  Future<UserModel> updatePassword(String newPassword) =>
      throw UnimplementedError();

  @override
  Future<bool> checkEmailVerified() => throw UnimplementedError();

  @override
  Future<void> resendVerificationEmail() => throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();

  @override
  Future<void> deleteAccount() => throw UnimplementedError();

  @override
  Future<void> updateUser(UserModel user) => throw UnimplementedError();

  @override
  Future<UserModel?> refreshCurrentUser() => throw UnimplementedError();
}

class _FakeStoreRepository implements StoreRepository {
  _FakeStoreRepository(this._stores);

  final List<StoreModel> _stores;

  @override
  Future<List<StoreModel>> allStores() async => _stores;

  @override
  Future<StoreModel> createStore(StoreModel store) async => store;

  @override
  Future<StoreModel?> storeById(String storeId) async =>
      _find((store) => store.id == storeId);

  @override
  Future<StoreModel?> storeBySlug(String slug) async =>
      _find((store) => store.slug == slug);

  @override
  Future<List<StoreModel>> storesForSeller(String sellerId) async =>
      _stores.where((store) => store.sellerId == sellerId).toList();

  @override
  Future<void> updateStore(StoreModel store) async {}

  @override
  Future<String> uploadStoreImage(
    String storeId,
    Uint8List bytes, {
    required String contentType,
    required String kind,
  }) async =>
      'https://example.test/$storeId/$kind';

  StoreModel? _find(bool Function(StoreModel store) predicate) {
    for (final store in _stores) {
      if (predicate(store)) return store;
    }
    return null;
  }
}
