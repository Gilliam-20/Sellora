import 'package:get/get.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/dio_client.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/cart_repository.dart';
import '../../data/repositories/firebase_admin_repository.dart';
import '../../data/repositories/firebase_fx_rate_repository.dart';
import '../../data/repositories/fx_rate_repository.dart';
import '../../data/repositories/firebase_order_repository.dart';
import '../../data/repositories/firebase_notification_repository.dart';
import '../../data/repositories/firebase_product_repository.dart';
import '../../data/repositories/firebase_store_repository.dart';
import '../../data/repositories/firebase_subscription_repository.dart';
import '../../data/repositories/mock/mock_admin_repository.dart';
import '../../data/repositories/mock/mock_fx_rate_repository.dart';
import '../../data/repositories/mock/mock_order_repository.dart';
import '../../data/repositories/mock/mock_notification_repository.dart';
import '../../data/repositories/mock/mock_product_repository.dart';
import '../../data/repositories/mock/mock_subscription_repository.dart';
import '../../data/repositories/order_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/repositories/store_repository.dart';
import '../../data/repositories/subscription_repository.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/cj_dropshipping_service.dart';
import '../../data/services/currency_service.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/intasend_service.dart';
import '../../data/services/storage_service.dart';
import '../../modules/storefront/store_scope.dart';
import '../../modules/notifications/notification_center.dart';

/// Everything the whole app needs for its entire lifetime is registered
/// here, once, as `permanent: true` — services, [AuthRepository] and
/// [StoreRepository] (always Firebase-backed), and whichever
/// implementation of the remaining repositories matches
/// [AppConstants.useMockData].
///
/// Every screen-level controller is registered instead by that route's
/// own BindingsBuilder with `Get.lazyPut`, so it's created only when
/// its page is pushed and disposed when the page is popped.
class InitialBinding extends Bindings {
  @override
  void dependencies() {
    // ---- App-wide services --------------------------------------------
    Get.put(StorageService(), permanent: true);
    // Reads StorageService.currencyCode in its constructor, so it must be
    // registered after it — same ordering reason as StoreScope below.
    Get.put(CurrencyService(), permanent: true);
    Get.put(DioClient(), permanent: true);
    Get.put(CartRepository(), permanent: true);

    // ---- Identity: always the real Firebase-backed implementation ------
    // Auth and the store a seller owns are never mocked, even while
    // AppConstants.useMockData is true for the rest of the app below.
    // MockAuthRepository/MockStoreRepository are in-memory only, so a real,
    // persisted Firebase Auth account would otherwise lose its own store on
    // every restart. See WORKLOG.md, 2026-09-25.
    Get.put(AuthService(), permanent: true);
    Get.put(FirestoreService(), permanent: true);
    // StoreRepository goes first — AuthRepository's signUpSeller resolves
    // it via Get.find in its own constructor, to create a store for every
    // newly-registered seller.
    Get.put<StoreRepository>(FirebaseStoreRepository(), permanent: true);
    Get.put<AuthRepository>(FirebaseAuthRepository(), permanent: true);

    if (AppConstants.useMockData) {
      // Demo mode for the rest of the app: no CJ Dropshipping or IntaSend
      // credentials required to browse the catalog, place orders, or
      // exercise subscriptions/admin — only signing in/up above talks to a
      // real backend.
      Get.put<ProductRepository>(MockProductRepository(), permanent: true);
      Get.put<OrderRepository>(MockOrderRepository(), permanent: true);
      Get.put<NotificationRepository>(MockNotificationRepository(),
          permanent: true);
      Get.put<SubscriptionRepository>(MockSubscriptionRepository(),
          permanent: true);
      Get.put<AdminRepository>(MockAdminRepository(), permanent: true);
      Get.put<FxRateRepository>(MockFxRateRepository(), permanent: true);
    } else {
      Get.put(CjDropshippingService(), permanent: true);
      Get.put(IntasendService(), permanent: true);

      Get.put<ProductRepository>(FirebaseProductRepository(), permanent: true);
      Get.put<OrderRepository>(FirebaseOrderRepository(), permanent: true);
      Get.put<NotificationRepository>(FirebaseNotificationRepository(),
          permanent: true);
      Get.put<SubscriptionRepository>(FirebaseSubscriptionRepository(),
          permanent: true);
      Get.put<AdminRepository>(FirebaseAdminRepository(), permanent: true);
      Get.put<FxRateRepository>(FirebaseFxRateRepository(), permanent: true);
    }

    // Fire-and-forget: display prices use FxRates.fallback until this lands.
    Get.find<CurrencyService>().refreshRates();

    // StoreScope resolves StoreRepository in its constructor, so it must be
    // registered after it (set above, before the mock/Firebase branch).
    Get.put(StoreScope(), permanent: true);
    Get.put(NotificationCenter(), permanent: true);
  }
}
