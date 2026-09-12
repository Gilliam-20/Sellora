import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/cart_repository.dart';
import '../../../data/services/storage_service.dart';

class AuthController extends GetxController {
  final AuthRepository _authRepo = Get.find<AuthRepository>();
  final StorageService _storage = Get.find<StorageService>();
  final CartRepository _cartRepo = Get.find<CartRepository>();

  final isLoading = false.obs;
  final errorMessage = RxnString();

  /// Called once from the splash screen. Waits briefly for Firebase to
  /// report whether a session already exists, then routes accordingly.
  Future<void> checkSession() async {
    try {
      final user = await _authRepo.userChanges.first.timeout(
        const Duration(seconds: 3),
        onTimeout: () => null,
      );
      if (user != null) {
        _goToHome(user);
        return;
      }
    } catch (_) {
      // No session, or mock mode with nothing cached yet — fall through.
    }
    // No signed-in user: lead with the marketing page rather than
    // dropping a first-time visitor straight into role select.
    Get.offAllNamed(Routes.marketing);
  }

  Future<void> signIn({required String email, required String password}) async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final user = await _authRepo.signIn(email: email, password: password);
      _storage.lastRole = user.role.name;
      _goToHome(user);
    } catch (e) {
      errorMessage.value = _friendlyError(e);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> registerBuyer({
    required String name,
    required String email,
    required String password,
    required String storeId,
  }) async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final user = await _authRepo.signUpBuyer(
          name: name, email: email, password: password, storeId: storeId);
      _storage.lastRole = user.role.name;
      _goToHome(user);
    } catch (e) {
      errorMessage.value = _friendlyError(e);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> registerSeller({
    required String name,
    required String email,
    required String password,
    required String storeName,
    required String phone,
  }) async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final user = await _authRepo.signUpSeller(
        name: name,
        email: email,
        password: password,
        storeName: storeName,
        phone: phone,
      );
      _storage.lastRole = user.role.name;
      Get.offAllNamed(Routes.sellerOnboarding);
    } catch (e) {
      errorMessage.value = _friendlyError(e);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> sendReset(String email) async {
    try {
      await _authRepo.sendPasswordReset(email);
    } catch (_) {
      // Deliberately silent — don't reveal whether an email is registered.
    }
  }

  Future<void> signOut() async {
    await _authRepo.signOut();
    _cartRepo.setStore(null);
    Get.offAllNamed(Routes.roleSelect);
  }

  void _goToHome(UserModel user) {
    switch (user.role) {
      case UserRole.buyer:
        _cartRepo.setStore(user.storeId);
        Get.offAllNamed(Routes.buyerShell);
        break;
      case UserRole.seller:
        Get.offAllNamed(user.hasActiveSubscription
            ? Routes.sellerShell
            : Routes.sellerOnboarding);
        break;
      case UserRole.admin:
        Get.offAllNamed(Routes.adminShell);
        break;
    }
  }

  String _friendlyError(Object e) {
    final message = e.toString();
    if (message.contains('user-not-found') ||
        message.contains('wrong-password')) {
      return 'That email and password combination doesn\'t match an account.';
    }
    if (message.contains('email-already-in-use')) {
      return 'An account already exists with that email.';
    }
    if (message.contains('weak-password')) {
      return 'Choose a stronger password (at least 8 characters).';
    }
    return 'Something went wrong. Please try again.';
  }
}
