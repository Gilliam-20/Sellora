// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get storeLoading => 'Loading store…';

  @override
  String get storeLoadFailedTitle => 'We couldn\'t load this store';

  @override
  String get storeNotFound => 'This storefront could not be found.';

  @override
  String get tryAgain => 'Try again';

  @override
  String get navShop => 'Shop';

  @override
  String get navCart => 'Cart';

  @override
  String get navOrders => 'Orders';

  @override
  String get navAlerts => 'Alerts';

  @override
  String get navProfile => 'Profile';

  @override
  String get storefrontAccount => 'Account';

  @override
  String get storefrontFallbackTitle => 'Storefront';

  @override
  String get storefrontFallbackTagline => 'Products selected for you.';

  @override
  String get storefrontSearchHint => 'Search this store';

  @override
  String get storefrontClosedTitle => 'This store isn’t open right now';

  @override
  String get storefrontClosedMessage => 'Please check back later.';

  @override
  String get storefrontEmptyTitle => 'No products are published yet';

  @override
  String get storefrontEmptyMessage =>
      'Check back soon for this store’s latest collection.';

  @override
  String get loadMore => 'Load more';

  @override
  String get cartTitle => 'Your cart';

  @override
  String get cartEmptyTitle => 'Your cart is empty';

  @override
  String get cartEmptyMessage => 'Products you add will show up here.';

  @override
  String get cartRemove => 'Remove';

  @override
  String get cartCheckout => 'Checkout';
}
