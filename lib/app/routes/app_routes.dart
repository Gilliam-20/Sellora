abstract class Routes {
  Routes._();

  static const splash = '/';
  static const roleSelect = '/role-select';
  static const login = '/login';
  static const storeSelect = '/select-store';
  static const registerBuyer = '/register/buyer';
  static const registerSeller = '/register/seller';

  static const sellerOnboarding = '/seller/onboarding';

  // Public tenant storefront. This remains separate from portal routes so a
  // later custom-domain resolver only has to populate StoreScope.
  static const storefront = '/s/:slug';

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
