import 'package:get/get.dart';
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
/// here, once, as `permanent: true` — services and every repository.
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

    // ---- Repositories: always the real Supabase-backed implementations --
    // There is no demo mode (removed 2026-09-26, see WORKLOG.md). Anything
    // that goes through ApiEndpoints fails until functions/ is ported to
    // Edge Functions.
    Get.put(AuthService(), permanent: true);
    Get.put(SupabaseService(), permanent: true);
    // Sign-up creates a seller's store server-side (the handle_new_user
    // trigger), so AuthRepository no longer depends on StoreRepository.
    Get.put<StoreRepository>(SupabaseStoreRepository(), permanent: true);
    Get.put<AuthRepository>(SupabaseAuthRepository(), permanent: true);

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

    // Fire-and-forget: display prices use FxRates.fallback until this lands.
    Get.find<CurrencyService>().refreshRates();

    // StoreScope resolves StoreRepository in its constructor, so it must be
    // registered after it.
    Get.put(StoreScope(), permanent: true);
    Get.put(NotificationCenter(), permanent: true);
  }
}
