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
    resolveStore();
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

  void changeTab(int index) => tabIndex.value = index;

  Future<void> signOut() async {
    await _authRepository.signOut();
    Get.offAllNamed(Routes.login);
  }
}
