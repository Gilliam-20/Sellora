abstract class Routes {
  Routes._();

  static const splash = '/';
  static const marketing = '/marketing';
  static const roleSelect = '/role-select';
  static const login = '/login';
  static const registerSeller = '/register/seller';
  static const sellerTerms = '/seller-terms';

  // Where a password-recovery link lands — see SelloraApp's onReady.
  static const resetPassword = '/reset-password';

  // Where an expired/used/wrong-device auth email link lands.
  static const authLinkError = '/auth-link-error';

  // Public account deletion, for the Play Console's deletion-link field:
  // https://<host>/#/delete-account
  static const deleteAccount = '/delete-account';

  static const sellerOnboarding = '/seller/onboarding';

  // Public tenant storefront (TODO §20): every page a customer sees lives
  // under the store's own /s/:slug, each with its own URL so it can be
  // shared, bookmarked or refreshed. One URL serves guests and signed-in
  // buyers alike. Kept apart from the portal routes so a later
  // custom-domain resolver only has to populate StorefrontSession.
  // Paths are built with StorefrontPaths (storefront_links.dart).
  static const storefront = '/s/:slug';
  static const storefrontShop = '/s/:slug/shop';
  static const storefrontSearch = '/s/:slug/search';
  static const storefrontCollections = '/s/:slug/collections';
  static const storefrontCollection = '/s/:slug/collections/:handle';
  static const storefrontCart = '/s/:slug/cart';
  static const storefrontOrder = '/s/:slug/orders/:orderId';
  static const storefrontAccount = '/s/:slug/account';
  static const storefrontOrders = '/s/:slug/account/orders';
  static const storefrontNotifications = '/s/:slug/account/notifications';
  static const storefrontPage = '/s/:slug/pages/:page';

  // Store-scoped buyer auth — a buyer registers/signs in as a customer of
  // this specific store, never through Sellora's own (seller-only) login.
  static const storefrontLogin = '/s/:slug/login';
  static const storefrontRegister = '/s/:slug/register';

  static const storefrontProduct = '/s/:slug/products/:productId';
  static const storefrontCheckout = '/s/:slug/checkout';

  // Seller portal
  static const sellerShell = '/seller';
  static const sellerProductImport = '/seller/import';
  static const sellerManageVariants = '/seller/variants';
  static const sellerStoreCustomize = '/seller/store/customize';
  static const sellerStoreDesign = '/seller/store/design';
  static const sellerStorePages = '/seller/store/pages';
  static const sellerSubscription = '/seller/subscription';
  static const sellerCustomers = '/seller/customers';
  static const sellerMarketing = '/seller/marketing';
  static const sellerOrderDetail = '/seller/orders/detail';

  // Admin portal
  static const adminShell = '/admin';
  static const adminActivity = '/admin/activity';
}
