import 'package:get/get.dart';
import '../../data/models/user_model.dart';
import '../../modules/admin/admin_binding.dart';
import '../../modules/admin/shell/admin_shell_view.dart';
import '../../modules/auth/bindings/auth_binding.dart';
import '../../modules/auth/views/login_view.dart';
import '../../modules/auth/views/register_seller_view.dart';
import '../../modules/auth/views/seller_terms_view.dart';
import '../../modules/auth/views/role_select_view.dart';
import '../../modules/auth/views/splash_view.dart';
import '../../modules/buyer/buyer_binding.dart';
import '../../modules/buyer/checkout/checkout_view.dart';
import '../../modules/buyer/product_details/product_details_view.dart';
import '../../modules/buyer/shell/buyer_shell_view.dart';
import '../../modules/marketing/marketing_controller.dart';
import '../../modules/marketing/marketing_view.dart';
import '../../modules/onboarding/bindings/seller_onboarding_binding.dart';
import '../../modules/onboarding/views/seller_onboarding_view.dart';
import '../../modules/seller/manage_variants/manage_variants_view.dart';
import '../../modules/seller/product_import/product_import_view.dart';
import '../../modules/seller/seller_binding.dart';
import '../../modules/seller/shell/seller_shell_view.dart';
import '../../modules/seller/store_customize/store_customize_view.dart';
import '../../modules/seller/subscription/seller_subscription_view.dart';
import '../../modules/storefront/storefront_binding.dart';
import '../../modules/storefront/storefront_login_view.dart';
import '../../modules/storefront/storefront_register_view.dart';
import 'app_routes.dart';
import 'role_middleware.dart';

class AppPages {
  AppPages._();

  static final pages = <GetPage>[
    GetPage(
        name: Routes.splash,
        page: () => const SplashView(),
        binding: AuthBinding()),
    GetPage(
        name: Routes.marketing,
        page: () => MarketingView(),
        binding: MarketingBinding()),
    GetPage(
        name: Routes.roleSelect,
        page: () => const RoleSelectView()),
    GetPage(
        name: Routes.login,
        page: () => const LoginView(),
        binding: AuthBinding()),
    GetPage(
        name: Routes.registerSeller,
        page: () => const RegisterSellerView(),
        binding: AuthBinding()),
    GetPage(name: Routes.sellerTerms, page: () => const SellerTermsView()),
    GetPage(
      name: Routes.storefront,
      page: () => const BuyerShellView(),
      bindings: [StorefrontBinding(), BuyerBinding()],
    ),
    GetPage(
      name: Routes.storefrontLogin,
      page: () => const StorefrontLoginView(),
      bindings: [StorefrontBinding(), AuthBinding()],
    ),
    GetPage(
      name: Routes.storefrontRegister,
      page: () => const StorefrontRegisterView(),
      bindings: [StorefrontBinding(), AuthBinding()],
    ),

    GetPage(
      name: Routes.sellerOnboarding,
      page: () => const SellerOnboardingView(),
      binding: SellerOnboardingBinding(),
      middlewares: [RoleMiddleware(UserRole.seller)],
    ),

    // ---- Buyer portal ------------------------------------------------
    // Pushed on top of the storefront shell (Routes.storefront above) —
    // still store-scoped via the shared :slug segment, own back-stack
    // entries. Guest-reachable for browsing/cart; CheckoutView gates its
    // own submit step behind sign-in rather than a route middleware, since
    // a guest should still be able to view a product and their cart.
    GetPage(
      name: Routes.storefrontProduct,
      page: () => const ProductDetailsView(),
      binding: ProductDetailsBinding(),
    ),
    GetPage(
      name: Routes.storefrontCheckout,
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
    GetPage(
      name: Routes.sellerProductImport,
      page: () => const ProductImportView(),
      binding: ProductImportBinding(),
      middlewares: [RoleMiddleware(UserRole.seller)],
    ),
    GetPage(
      name: Routes.sellerManageVariants,
      page: () => const ManageVariantsView(),
      binding: ManageVariantsBinding(),
      middlewares: [RoleMiddleware(UserRole.seller)],
    ),
    GetPage(
      name: Routes.sellerStoreCustomize,
      page: () => const StoreCustomizeView(),
      binding: StoreCustomizeBinding(),
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
