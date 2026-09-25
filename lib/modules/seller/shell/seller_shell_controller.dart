import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../storefront/store_scope.dart';
import '../../notifications/notification_center.dart';

class SellerShellController extends GetxController {
  SellerShellController({AuthRepository? authRepository, StoreScope? scope})
      : _authRepository = authRepository ?? Get.find<AuthRepository>(),
        scope = scope ?? Get.find<StoreScope>();

  final AuthRepository _authRepository;
  final StoreScope scope;

  final tabIndex = 0.obs;

  @override
  void onInit() {
    super.onInit();
    // Deferred a frame: resolveStore() flips StoreScope.isResolving/current
    // (Rx values the shell's own Obx reads) — calling it synchronously here
    // runs it while GetView's Get.find<SellerShellController>() is still
    // instantiating this controller mid-build (re-navigating to `/seller`,
    // e.g. right after sign-in, can hit this), throwing "setState()/
    // markNeedsBuild() called during build" — same bug fixed for
    // BuyerShellController's identical resolveStore() pattern.
    WidgetsBinding.instance.addPostFrameCallback((_) => resolveStore());
    final user = _authRepository.cachedUser;
    if (user != null) Get.find<NotificationCenter>().start(user.uid);
  }

  void resolveStore() {
    final user = _authRepository.cachedUser;
    // No signed-in seller shouldn't happen here — RoleMiddleware guards this
    // shell — but resolving is a no-op rather than a crash if it ever does.
    if (user != null) {
      scope.resolveForSeller(user.uid);
    }
  }

  /// Onboarding's store-setup step creates a store when the seller has
  /// none, then routes back here.
  void setUpStore() => Get.offAllNamed(Routes.sellerOnboarding);

  void changeTab(int index) => tabIndex.value = index;

  Future<void> signOut() async {
    await _authRepository.signOut();
    Get.offAllNamed(Routes.login);
  }
}
