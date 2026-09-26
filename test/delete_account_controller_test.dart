import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sellora/core/network/api_exception.dart';
import 'package:sellora/data/models/user_model.dart';
import 'package:sellora/data/repositories/auth_repository.dart';
import 'package:sellora/data/repositories/cart_repository.dart';
import 'package:sellora/modules/auth/controllers/delete_account_controller.dart';
import 'fakes/mock_auth_repository.dart';
import 'fakes/mock_store_repository.dart';

/// Signs in like the fake, but can be told to refuse the deletion or the
/// sign-in itself.
class _Auth extends MockAuthRepository {
  _Auth() : super(storeRepository: MockStoreRepository());

  Object? signInError;
  Object? deleteError;
  int deletes = 0;

  @override
  Future<UserModel> signIn(
      {required String email, required String password, String? storeId}) {
    if (signInError != null) throw signInError!;
    return super.signIn(email: email, password: password, storeId: storeId);
  }

  @override
  Future<void> deleteAccount() async {
    deletes++;
    if (deleteError != null) throw deleteError!;
    return super.deleteAccount();
  }
}

void main() {
  tearDown(Get.reset);

  test('signs in, deletes, and leaves nobody signed in', () async {
    final auth = _Auth();
    final cart = CartRepository()..setStore('store-1');
    final c =
        DeleteAccountController(authRepository: auth, cartRepository: cart);

    await c.deleteAccount(email: 'a@example.com', password: 'password123');

    expect(c.deleted.value, isTrue);
    expect(c.errorMessage.value, isNull);
    expect(auth.cachedUser, isNull);
    expect(cart.storeId, isNull);
  });

  test('a wrong password deletes nothing', () async {
    final auth = _Auth()..signInError = const AuthFailure('invalid-credential');
    final c = DeleteAccountController(
        authRepository: auth, cartRepository: CartRepository());

    await c.deleteAccount(email: 'a@example.com', password: 'nope');

    expect(auth.deletes, 0);
    expect(c.deleted.value, isFalse);
    expect(c.errorMessage.value, contains('doesn\'t match an account'));
  });

  test('a refused deletion shows why and signs back out', () async {
    final auth = _Auth()
      ..deleteError = ApiException(
          'You have orders that are still being delivered.',
          statusCode: 409);
    final c = DeleteAccountController(
        authRepository: auth, cartRepository: CartRepository());

    await c.deleteAccount(email: 'a@example.com', password: 'password123');

    expect(c.deleted.value, isFalse);
    expect(c.errorMessage.value, contains('still being delivered'));
    expect(auth.cachedUser, isNull);
    expect(c.isLoading.value, isFalse);
  });
}
