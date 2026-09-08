import 'package:get/get.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/dio_client.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/cart_repository.dart';
import '../../data/repositories/firebase_admin_repository.dart';
import '../../data/repositories/firebase_order_repository.dart';
import '../../data/repositories/firebase_product_repository.dart';
import '../../data/repositories/firebase_store_repository.dart';
import '../../data/repositories/firebase_subscription_repository.dart';
import '../../data/repositories/mock/mock_admin_repository.dart';
import '../../data/repositories/mock/mock_auth_repository.dart';
import '../../data/repositories/mock/mock_order_repository.dart';
import '../../data/repositories/mock/mock_product_repository.dart';
import '../../data/repositories/mock/mock_store_repository.dart';
import '../../data/repositories/mock/mock_subscription_repository.dart';
import '../../data/repositories/order_repository.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/repositories/store_repository.dart';
import '../../data/repositories/subscription_repository.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/cj_dropshipping_service.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/intasend_service.dart';
import '../../data/services/storage_service.dart';

/// Everything the whole app needs for its entire lifetime is registered
/// here, once, as `permanent: true` — services, and whichever
/// repository implementation matches [AppConstants.useMockData].
///
/// Every screen-level controller is registered instead by that route's
/// own BindingsBuilder with `Get.lazyPut`, so it's created only when
/// its page is pushed and disposed when the page is popped.
class InitialBinding extends Bindings {
  @override
  void dependencies() {
    // ---- App-wide services --------------------------------------------
    Get.put(StorageService(), permanent: true);
    Get.put(DioClient(), permanent: true);
    Get.put(CartRepository(), permanent: true);

    if (AppConstants.useMockData) {
      // Demo mode: no Firebase project, IntaSend, or CJ Dropshipping
      // credentials required.
      Get.put<AuthRepository>(MockAuthRepository(), permanent: true);
      Get.put<ProductRepository>(MockProductRepository(), permanent: true);
      Get.put<OrderRepository>(MockOrderRepository(), permanent: true);
      Get.put<SubscriptionRepository>(MockSubscriptionRepository(),
          permanent: true);
      Get.put<AdminRepository>(MockAdminRepository(), permanent: true);
      Get.put<StoreRepository>(MockStoreRepository(), permanent: true);
    } else {
      Get.put(AuthService(), permanent: true);
      Get.put(FirestoreService(), permanent: true);
      Get.put(CjDropshippingService(), permanent: true);
      Get.put(IntasendService(), permanent: true);

      Get.put<AuthRepository>(FirebaseAuthRepository(), permanent: true);
      Get.put<ProductRepository>(FirebaseProductRepository(), permanent: true);
      Get.put<OrderRepository>(FirebaseOrderRepository(), permanent: true);
      Get.put<SubscriptionRepository>(FirebaseSubscriptionRepository(),
          permanent: true);
      Get.put<AdminRepository>(FirebaseAdminRepository(), permanent: true);
      Get.put<StoreRepository>(FirebaseStoreRepository(), permanent: true);
    }
  }
}
