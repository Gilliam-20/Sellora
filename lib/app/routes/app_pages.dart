import 'package:get/get.dart';
import '../../data/models/user_model.dart';
import '../../modules/admin/admin_binding.dart';
import '../../modules/admin/shell/admin_shell_view.dart';
import '../../modules/auth/bindings/auth_binding.dart';
import '../../modules/auth/views/login_view.dart';
import '../../modules/auth/views/register_buyer_view.dart';
import '../../modules/auth/views/register_seller_view.dart';
import '../../modules/auth/views/role_select_view.dart';
import '../../modules/auth/views/splash_view.dart';
import '../../modules/auth/views/store_select_view.dart';
import '../../modules/buyer/buyer_binding.dart';
import '../../modules/buyer/checkout/checkout_view.dart';
import '../../modules/buyer/product_details/product_details_view.dart';
import '../../modules/buyer/shell/buyer_shell_view.dart';
import '../../modules/onboarding/bindings/seller_onboarding_binding.dart';
import '../../modules/onboarding/views/seller_onboarding_view.dart';
import '../../modules/seller/seller_binding.dart';
import '../../modules/seller/shell/seller_shell_view.dart';
import '../../modules/seller/subscription/seller_subscription_view.dart';
import 'app_routes.dart';
import 'role_middleware.dart';

class AppPages {
  AppPages._();

  static final pages = <GetPage>[
    GetPage(
        name: Routes.splash,
        page: () => const SplashView(),
        binding: AuthBinding()),
    GetPage(name: Routes.roleSelect, page: () => const RoleSelectView()),
    GetPage(
        name: Routes.login,
        page: () => const LoginView(),
        binding: AuthBinding()),
    GetPage(
        name: Routes.storeSelect,
        page: () => const StoreSelectView(),
        binding: AuthBinding()),
    GetPage(
        name: Routes.registerBuyer,
        page: () => const RegisterBuyerView(),
        binding: AuthBinding()),
    GetPage(
        name: Routes.registerSeller,
        page: () => const RegisterSellerView(),
        binding: AuthBinding()),

    GetPage(
      name: Routes.sellerOnboarding,
      page: () => const SellerOnboardingView(),
      binding: SellerOnboardingBinding(),
      middlewares: [RoleMiddleware(UserRole.seller)],
    ),

    // ---- Buyer portal ----------------------------------------------------
    GetPage(
      name: Routes.buyerShell,
      page: () => const BuyerShellView(),
      binding: BuyerBinding(),
      middlewares: [RoleMiddleware(UserRole.buyer)],
    ),
    GetPage(
      name: Routes.buyerProductDetails,
      page: () => const ProductDetailsView(),
      binding: ProductDetailsBinding(),
    ),
    GetPage(
      name: Routes.buyerCheckout,
      page: () => const CheckoutView(),
      binding: CheckoutBinding(),
    ),

    // ---- Seller portal ------------------------------------------------
    GetPage(
      name: Routes.sellerShell,
      page: () => const SellerShellView(),
      binding: SellerBinding(),
      middlewares: [RoleMiddleware(UserRole.seller)],
    ),
    GetPage(
      name: Routes.sellerSubscription,
      page: () => const SellerSubscriptionView(),
      binding: SellerSubscriptionBinding(),
      middlewares: [RoleMiddleware(UserRole.seller)],
    ),

    // ---- Admin portal -------------------------------------------------
    GetPage(
      name: Routes.adminShell,
      page: () => const AdminShellView(),
      binding: AdminBinding(),
      middlewares: [RoleMiddleware(UserRole.admin)],
    ),
  ];
}
