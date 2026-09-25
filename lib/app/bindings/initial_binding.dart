import 'package:get/get.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/dio_client.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/cart_repository.dart';
import '../../data/repositories/supabase_admin_repository.dart';
import '../../data/repositories/supabase_fx_rate_repository.dart';
import '../../data/repositories/fx_rate_repository.dart';
import '../../data/repositories/supabase_order_repository.dart';
import '../../data/repositories/supabase_notification_repository.dart';
import '../../data/repositories/supabase_product_repository.dart';
import '../../data/repositories/supabase_store_repository.dart';
import '../../data/repositories/supabase_subscription_repository.dart';
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
import '../../data/services/supabase_service.dart';
import '../../data/services/intasend_service.dart';
import '../../data/services/storage_service.dart';
import '../../modules/storefront/store_scope.dart';
import '../../modules/notifications/notification_center.dart';

/// Everything the whole app needs for its entire lifetime is registered
/// here, once, as `permanent: true` — services, [AuthRepository] and
/// [StoreRepository] (always Supabase-backed), and whichever
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

    // ---- Identity: always the real Supabase-backed implementation ------
    // Auth and the store a seller owns are never mocked, even while
    // AppConstants.useMockData is true for the rest of the app below.
    // MockAuthRepository/MockStoreRepository are in-memory only, so a real,
    // persisted Supabase account would otherwise lose its own store on
    // every restart. See WORKLOG.md, 2026-09-25 and 2026-09-26.
    Get.put(AuthService(), permanent: true);
    Get.put(SupabaseService(), permanent: true);
    // Sign-up creates a seller's store server-side (the handle_new_user
    // trigger), so AuthRepository no longer depends on StoreRepository.
    Get.put<StoreRepository>(SupabaseStoreRepository(), permanent: true);
    Get.put<AuthRepository>(SupabaseAuthRepository(), permanent: true);

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

      Get.put<ProductRepository>(SupabaseProductRepository(), permanent: true);
      Get.put<OrderRepository>(SupabaseOrderRepository(), permanent: true);
      Get.put<NotificationRepository>(SupabaseNotificationRepository(),
          permanent: true);
      Get.put<SubscriptionRepository>(SupabaseSubscriptionRepository(),
          permanent: true);
      Get.put<AdminRepository>(SupabaseAdminRepository(), permanent: true);
      Get.put<FxRateRepository>(SupabaseFxRateRepository(), permanent: true);
    }

    // Fire-and-forget: display prices use FxRates.fallback until this lands.
    Get.find<CurrencyService>().refreshRates();

    // StoreScope resolves StoreRepository in its constructor, so it must be
    // registered after it (set above, before the mock/Supabase branch).
    Get.put(StoreScope(), permanent: true);
    Get.put(NotificationCenter(), permanent: true);
  }
}
