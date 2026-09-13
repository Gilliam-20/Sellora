abstract class Routes {
  Routes._();

  static const splash = '/';
  static const marketing = '/marketing';
  static const roleSelect = '/role-select';
  static const login = '/login';
  static const registerSeller = '/register/seller';

  static const sellerOnboarding = '/seller/onboarding';

  // Public tenant storefront. This remains separate from portal routes so a
  // later custom-domain resolver only has to populate StoreScope.
  static const storefront = '/s/:slug';

  // Store-scoped buyer auth — a buyer registers/signs in as a customer of
  // this specific store, never through Sellora's own (seller-only) login.
  static const storefrontLogin = '/s/:slug/login';
  static const storefrontRegister = '/s/:slug/register';

  // Buyer portal
  static const buyerShell = '/buyer';
  static const buyerProductDetails = '/buyer/product';
  static const buyerCheckout = '/buyer/checkout';

  // Seller portal
  static const sellerShell = '/seller';
  static const sellerAddListing = '/seller/add-listing';
  static const sellerSubscription = '/seller/subscription';

  // Admin portal
  static const adminShell = '/admin';
}
