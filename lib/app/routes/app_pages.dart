import 'package:get/get.dart';
import '../../data/models/user_model.dart';
import '../../modules/admin/activity/admin_activity_view.dart';
import '../../modules/admin/admin_binding.dart';
import '../../modules/admin/shell/admin_shell_view.dart';
import '../../modules/auth/bindings/auth_binding.dart';
import '../../modules/auth/views/login_view.dart';
import '../../modules/auth/views/reset_password_view.dart';
import '../../modules/auth/views/auth_link_error_view.dart';
import '../../modules/auth/views/delete_account_view.dart';
import '../../modules/auth/views/register_seller_view.dart';
import '../../modules/auth/views/seller_terms_view.dart';
import '../../modules/auth/views/role_select_view.dart';
import '../../modules/auth/views/splash_view.dart';
import '../../modules/buyer/buyer_binding.dart';
import '../../modules/buyer/cart/cart_view.dart';
import '../../modules/buyer/checkout/checkout_view.dart';
import '../../modules/buyer/orders/buyer_orders_view.dart';
import '../../modules/buyer/orders/order_page.dart';
import '../../modules/buyer/product_details/product_details_view.dart';
import '../../modules/buyer/profile/buyer_profile_view.dart';
import '../../modules/notifications/notifications_view.dart';
import '../../modules/marketing/marketing_controller.dart';
import '../../modules/marketing/marketing_view.dart';
import '../../modules/onboarding/bindings/seller_onboarding_binding.dart';
import '../../modules/onboarding/views/seller_onboarding_view.dart';
import '../../modules/seller/customers/seller_customers_view.dart';
import '../../modules/seller/manage_variants/manage_variants_view.dart';
import '../../modules/seller/marketing/seller_marketing_view.dart';
import '../../modules/seller/orders/seller_order_detail_view.dart';
import '../../modules/seller/product_import/product_import_view.dart';
import '../../modules/seller/seller_binding.dart';
import '../../modules/seller/shell/seller_shell_view.dart';
import '../../modules/seller/store_customize/store_customize_view.dart';
import '../../modules/seller/store_builder/store_builder_view.dart';
import '../../modules/seller/store_pages/store_pages_view.dart';
import '../../modules/seller/subscription/seller_subscription_view.dart';
import '../../modules/storefront/pages/product_list_page.dart';
import '../../modules/storefront/pages/store_page_view.dart';
import '../../modules/storefront/shell/storefront_page.dart';
import '../../modules/storefront/storefront_binding.dart';
import '../../modules/storefront/storefront_login_view.dart';
import '../../modules/storefront/storefront_register_view.dart';
import '../../modules/storefront/storefront_view.dart';
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
    GetPage(name: Routes.roleSelect, page: () => const RoleSelectView()),
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
        name: Routes.resetPassword,
        page: () => const ResetPasswordView(),
        binding: AuthBinding()),
    GetPage(name: Routes.authLinkError, page: () => const AuthLinkErrorView()),
    GetPage(
      name: Routes.deleteAccount,
      page: () => const DeleteAccountView(),
      binding: DeleteAccountBinding(),
    ),
    // ---- Storefront (TODO §20) ------------------------------------------
    // Guest-reachable throughout: checkout, the order page and the order
    // history ask for sign-in themselves rather than through a middleware,
    // so a guest can still browse and fill a cart.
    GetPage(
      name: Routes.storefront,
      page: () => const StorefrontView(),
      binding: StorefrontBinding(),
    ),
    GetPage(
      name: Routes.storefrontShop,
      page: () => const ProductListPage(mode: ProductListMode.shop),
    ),
    GetPage(
      name: Routes.storefrontSearch,
      page: () => const ProductListPage(mode: ProductListMode.search),
    ),
    GetPage(
      name: Routes.storefrontCollections,
      page: () => const CollectionsPage(),
    ),
    GetPage(
      name: Routes.storefrontCollection,
      page: () => const ProductListPage(mode: ProductListMode.collection),
    ),
    GetPage(
      name: Routes.storefrontProduct,
      page: () => const ProductDetailsView(),
      binding: ProductDetailsBinding(),
    ),
    GetPage(
      name: Routes.storefrontCart,
      page: () => const CartView(),
      binding: CartBinding(),
    ),
    GetPage(
      name: Routes.storefrontCheckout,
      page: () => const CheckoutView(),
      binding: CheckoutBinding(),
    ),
    GetPage(
      name: Routes.storefrontOrder,
      page: () => const OrderPage(),
      binding: OrderPageBinding(),
    ),
    GetPage(
      name: Routes.storefrontAccount,
      page: () => const BuyerProfileView(),
    ),
    GetPage(
      name: Routes.storefrontOrders,
      page: () => const BuyerOrdersView(),
      binding: BuyerOrdersBinding(),
    ),
    GetPage(
      name: Routes.storefrontNotifications,
      page: () => StorefrontFrame(
          title: 'Notifications',
          builder: (_, __, ___) => const NotificationsView()),
    ),
    GetPage(
      name: Routes.storefrontPage,
      page: () => const StorePageView(),
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
    GetPage(
      name: Routes.sellerStoreDesign,
      page: () => const StoreBuilderView(),
      binding: StoreBuilderBinding(),
      middlewares: [RoleMiddleware(UserRole.seller)],
    ),
    GetPage(
      name: Routes.sellerStorePages,
      page: () => const StorePagesView(),
      binding: StorePagesBinding(),
      middlewares: [RoleMiddleware(UserRole.seller)],
    ),
    GetPage(
      name: Routes.sellerCustomers,
      page: () => const SellerCustomersView(),
      binding: SellerCustomersBinding(),
      middlewares: [RoleMiddleware(UserRole.seller)],
    ),
    GetPage(
      name: Routes.sellerMarketing,
      page: () => const SellerMarketingView(),
      binding: SellerMarketingBinding(),
      middlewares: [RoleMiddleware(UserRole.seller)],
    ),
    GetPage(
      name: Routes.sellerOrderDetail,
      page: () => const SellerOrderDetailView(),
      binding: SellerOrderDetailBinding(),
      middlewares: [RoleMiddleware(UserRole.seller)],
    ),

    // ---- Admin portal -------------------------------------------------
    GetPage(
      name: Routes.adminShell,
      page: () => const AdminShellView(),
      binding: AdminBinding(),
      middlewares: [RoleMiddleware(UserRole.admin)],
    ),
    GetPage(
      name: Routes.adminActivity,
      page: () => const AdminActivityView(),
      binding: AdminActivityBinding(),
      middlewares: [RoleMiddleware(UserRole.admin)],
    ),
  ];
}
