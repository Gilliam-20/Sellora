import 'package:get/get.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../storefront/store_scope.dart';

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
    final user = _authRepository.cachedUser;
    // No signed-in seller shouldn't happen here — RoleMiddleware guards this
    // shell — but resolving is a no-op rather than a crash if it ever does.
    if (user != null) {
      scope.resolveForSeller(user.uid);
    }
  }

  void changeTab(int index) => tabIndex.value = index;
}
