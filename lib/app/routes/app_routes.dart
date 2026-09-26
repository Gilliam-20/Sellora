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

  static const sellerOnboarding = '/seller/onboarding';

  // Public tenant storefront — also the buyer shell (shop/cart/orders/
  // profile tabs). One URL serves guests and signed-in buyers alike, so
  // signing in never changes the address. This remains separate from other
  // portal routes so a later custom-domain resolver only has to populate
  // StoreScope.
  static const storefront = '/s/:slug';

  // Store-scoped buyer auth — a buyer registers/signs in as a customer of
  // this specific store, never through Sellora's own (seller-only) login.
  static const storefrontLogin = '/s/:slug/login';
  static const storefrontRegister = '/s/:slug/register';

  // Pushed on top of the storefront shell — still store-scoped, but their
  // own back-stack entries rather than shell tabs.
  static const storefrontProduct = '/s/:slug/product';
  static const storefrontCheckout = '/s/:slug/checkout';

  // Seller portal
  static const sellerShell = '/seller';
  static const sellerProductImport = '/seller/import';
  static const sellerManageVariants = '/seller/variants';
  static const sellerStoreCustomize = '/seller/store/customize';
  static const sellerSubscription = '/seller/subscription';

  // Admin portal
  static const adminShell = '/admin';
}
