import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/cart_repository.dart';
import '../../../data/repositories/store_repository.dart';
import '../../../data/services/storage_service.dart';

class AuthController extends GetxController {
  final AuthRepository _authRepo = Get.find<AuthRepository>();
  final StorageService _storage = Get.find<StorageService>();
  final CartRepository _cartRepo = Get.find<CartRepository>();
  final StoreRepository _storeRepo = Get.find<StoreRepository>();

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
        await _goToHome(user);
        return;
      }
    } catch (_) {
      // No session, or mock mode with nothing cached yet — fall through.
    }
    // No signed-in user: web leads with the marketing page (its
    // initialRoute skips splash entirely, but this also covers a direct
    // deep link to '/'); mobile has no address bar to hand a first-time
    // visitor a store's URL, so it continues splash → role select instead.
    Get.offAllNamed(kIsWeb ? Routes.marketing : Routes.roleSelect);
  }

  /// Sellora's own sign-in — seller/admin only. A buyer account is rejected
  /// rather than silently routed to the buyer portal, since a buyer should
  /// never authenticate through Sellora's own login.
  Future<void> signIn({required String email, required String password}) async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final user = await _authRepo.signIn(email: email, password: password);
      if (user.role == UserRole.buyer) {
        await _authRepo.signOut();
        errorMessage.value =
            'This is the seller sign-in. Buyers sign in from their store\'s page.';
        return;
      }
      _storage.lastRole = user.role.name;
      await _goToHome(user);
    } catch (e) {
      errorMessage.value = _friendlyError(e);
    } finally {
      isLoading.value = false;
    }
  }

  /// Store-scoped buyer sign-in, used only from a store's own storefront
  /// (e.g. `/s/{slug}/login`) — rejects an account that isn't a buyer of
  /// exactly this store, so signing in from the wrong store's page can't
  /// silently attach the wrong cart/order history.
  Future<void> signInToStore({
    required String email,
    required String password,
    required String storeId,
  }) async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final user = await _authRepo.signIn(
          email: email, password: password, storeId: storeId);
      if (user.role != UserRole.buyer || user.storeId != storeId) {
        await _authRepo.signOut();
        errorMessage.value = 'This account isn\'t registered with this store.';
        return;
      }
      _storage.lastRole = user.role.name;
      await _goToHome(user);
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
      await _goToHome(user);
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
    required bool hasAcceptedTerms,
  }) async {
    if (!hasAcceptedTerms) {
      errorMessage.value = 'Please accept the Seller Terms & Conditions to continue.';
      return;
    }
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final user = await _authRepo.signUpSeller(
        name: name,
        email: email,
        password: password,
        storeName: storeName,
        phone: phone,
        hasAcceptedTerms: hasAcceptedTerms,
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
    Get.offAllNamed(Routes.login);
  }

  Future<void> _goToHome(UserModel user) async {
    switch (user.role) {
      case UserRole.buyer:
        _cartRepo.setStore(user.storeId);
        await _goToBuyerStore(user.storeId);
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

  /// A buyer's home is their own store's `/s/{slug}`. Sign-in/registration
  /// already happen from that exact route, so the slug is almost always
  /// already in `Get.parameters` — the store lookup below only runs for the
  /// cold-start case (`checkSession()` resuming a cached session from the
  /// splash screen, which carries no `:slug`).
  Future<void> _goToBuyerStore(String? storeId) async {
    final routeSlug = Get.parameters['slug'];
    String? slug = routeSlug != null && routeSlug.isNotEmpty ? routeSlug : null;
    if (slug == null && storeId != null) {
      slug = (await _storeRepo.storeById(storeId))?.slug;
    }
    Get.offAllNamed(slug != null ? '/s/$slug' : Routes.marketing);
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
