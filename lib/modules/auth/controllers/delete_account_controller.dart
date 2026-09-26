import 'package:get/get.dart';
import '../../../core/network/api_exception.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/cart_repository.dart';
import 'auth_controller.dart';

/// Backs the public `/delete-account` page, the web link Google Play asks
/// for alongside the in-app `DeleteAccountButton`. It takes an email and
/// password rather than trusting whatever session the browser holds, so a
/// shared computer can't delete the last person's account, then goes
/// through the same server path as the button (`POST /deleteAccount`).
class DeleteAccountController extends GetxController {
  DeleteAccountController({
    AuthRepository? authRepository,
    CartRepository? cartRepository,
  })  : _authRepo = authRepository ?? Get.find<AuthRepository>(),
        _cartRepo = cartRepository ?? Get.find<CartRepository>();

  final AuthRepository _authRepo;
  final CartRepository _cartRepo;

  final isLoading = false.obs;
  final errorMessage = RxnString();
  final deleted = false.obs;

  Future<void> deleteAccount(
      {required String email, required String password}) async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      try {
        await _authRepo.signIn(email: email, password: password);
      } catch (e) {
        errorMessage.value = AuthController.friendlyError(e);
        return;
      }
      try {
        // Signs out on success.
        await _authRepo.deleteAccount();
        _cartRepo.setStore(null);
        deleted.value = true;
      } catch (e) {
        // Refused (e.g. a paid order still in fulfilment) or unreachable:
        // don't leave the session this page opened behind.
        errorMessage.value = e is ApiException
            ? e.message
            : 'Your account wasn\'t deleted. Please try again.';
        await _authRepo.signOut();
      }
    } finally {
      isLoading.value = false;
    }
  }
}
