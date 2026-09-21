import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/cart_repository.dart';
import '../../notifications/notification_center.dart';
import '../../storefront/store_scope.dart';

class BuyerShellController extends GetxController {
  BuyerShellController({
    AuthRepository? authRepository,
    StoreScope? scope,
    CartRepository? cartRepository,
  })  : _authRepository = authRepository ?? Get.find<AuthRepository>(),
        scope = scope ?? Get.find<StoreScope>(),
        _cartRepository = cartRepository ?? Get.find<CartRepository>();

  final AuthRepository _authRepository;
  final StoreScope scope;
  final CartRepository _cartRepository;

  final tabIndex = 0.obs;

  @override
  void onInit() {
    super.onInit();
    // Consumed once here rather than in the view's build() — reading
    // Get.arguments from build() would re-apply the initial tab (and
    // stomp on wherever the user has since navigated to) on every
    // rebuild, including the MediaQuery-driven rebuilds a responsive
    // layout triggers on resize.
    final args = Get.arguments as Map?;
    final initialTab = args?['tab'];
    if (initialTab is int) tabIndex.value = initialTab;
    // Deferred a frame: resolveStore() flips StoreScope.isResolving/current
    // (Rx values the shell's own Obx reads) — calling it synchronously here
    // runs it while GetView's Get.find<BuyerShellController>() is still
    // instantiating this controller mid-build (re-navigating to the same
    // `/s/:slug` route, e.g. right after sign-in, can hit this), throwing
    // "setState()/markNeedsBuild() called during build" (same class of bug
    // as StorefrontLoginView/StorefrontRegisterView's initState fix).
    WidgetsBinding.instance.addPostFrameCallback((_) => resolveStore());
  }

  /// Resolves the store this shell is scoped to from the route's `:slug` —
  /// same shape as SellerShellController.resolveStore(), so the view can
  /// gate rendering on scope.isResolving/current/errorMessage the same way.
  /// Sets the cart's store regardless of auth state, since a guest can
  /// browse and add to cart before ever signing in.
  Future<void> resolveStore() async {
    final slug = Get.parameters['slug'];
    if (slug == null || slug.isEmpty) return;
    final store = await scope.resolveSlug(slug);
    if (store == null) return;
    _cartRepository.setStore(store.id);
    final user = _authRepository.cachedUser;
    if (user != null && user.storeId == store.id) {
      Get.find<NotificationCenter>().start(user.uid);
    }
  }

  void changeTab(int index) => tabIndex.value = index;
}
