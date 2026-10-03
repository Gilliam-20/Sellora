import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../data/models/store_design.dart';
import '../../data/models/store_model.dart';
import '../../data/models/store_page.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/cart_repository.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/repositories/store_design_repository.dart';
import '../../data/repositories/store_page_repository.dart';
import '../notifications/notification_center.dart';
import 'design/store_branding.dart';
import 'store_scope.dart';

/// The storefront a visitor is in (TODO §20): the store from the URL's
/// `:slug`, its published design, its own pages and its categories, loaded
/// once and shared by every storefront page. Each page calls [ensure] with
/// its slug, so any of them can be the first one opened (a shared product
/// link, a refresh on the cart) and still find the store.
///
/// The store itself lives in [StoreScope], which the seller shell shares.
class StorefrontSession extends GetxService {
  StorefrontSession({
    StoreScope? scope,
    StoreDesignRepository? designs,
    StorePageRepository? pages,
    ProductRepository? products,
    CartRepository? cart,
    AuthRepository? auth,
  })  : scope = scope ?? Get.find<StoreScope>(),
        _designs = designs ?? Get.find<StoreDesignRepository>(),
        _pages = pages ?? Get.find<StorePageRepository>(),
        _products = products ?? Get.find<ProductRepository>(),
        _cart = cart ?? Get.find<CartRepository>(),
        _auth = auth ?? Get.find<AuthRepository>();

  final StoreScope scope;
  final StoreDesignRepository _designs;
  final StorePageRepository _pages;
  final ProductRepository _products;
  final CartRepository _cart;
  final AuthRepository _auth;

  /// The published design, or [StoreDesign.starter]; null while loading.
  final design = Rxn<StoreDesign>();

  /// The seller's published pages.
  final pages = <StorePageKind, StorePage>{}.obs;

  /// The categories with listed products, A–Z.
  final categories = <String>[].obs;

  String? _slug;

  /// The load of [_slug], finished or not; null after a failed one.
  Future<void>? _loading;

  StoreModel? get store => scope.current.value;

  /// The store's slug, for building links.
  String get slug => store?.slug ?? _slug ?? '';

  /// Whether [slug]'s store and design are loaded.
  bool isReadyFor(String slug) =>
      _normalize(slug) == _slug && store?.slug == _slug && design.value != null;

  /// The signed-in buyer, if they're a customer of this store.
  UserModel? get customer {
    final user = _auth.cachedUser;
    final s = store;
    return user != null &&
            s != null &&
            user.role == UserRole.buyer &&
            user.storeId == s.id
        ? user
        : null;
  }

  static String _normalize(String slug) => slug.trim().toLowerCase();

  /// Loads [slug]'s store unless it's already loaded or loading. A failed
  /// load can be retried by calling again.
  Future<void> ensure(String slug) {
    final s = _normalize(slug);
    if (s.isEmpty) return Future.value();
    // Already loaded or loading — unless something else (the seller shell)
    // has since put another store in StoreScope.
    final loading = _loading;
    if (s == _slug &&
        loading != null &&
        (design.value == null || store?.slug == s)) {
      _startNotifications();
      return loading;
    }
    _slug = s;
    return _loading = _load(s);
  }

  /// Loads the current store again (pull to refresh, retry).
  Future<void> reload() {
    final s = _slug;
    _loading = null;
    return s == null ? Future.value() : ensure(s);
  }

  Future<void> _load(String slug) async {
    design.value = null;
    pages.clear();
    categories.clear();
    final store = await scope.resolveSlug(slug);
    if (store == null) {
      _loading = null; // so the error screen's retry loads again
      return;
    }
    _cart.setStore(store.id);
    _startNotifications();
    StoreDesign? published;
    await Future.wait([
      () async {
        try {
          published = await _designs.publishedDesign(store.id);
        } catch (e) {
          // The storefront still works on the starter layout.
          debugPrint('StorefrontSession: design load failed: $e');
        }
      }(),
      () async {
        try {
          pages.assignAll(await _pages.publishedPages(store.id));
        } catch (e) {
          debugPrint('StorefrontSession: pages load failed: $e');
        }
      }(),
      () async {
        try {
          categories.assignAll(await _products.storeCategories(store.id));
        } catch (e) {
          debugPrint('StorefrontSession: categories load failed: $e');
        }
      }(),
    ]);
    if (scope.current.value?.id != store.id) return; // navigated elsewhere
    design.value = published ?? StoreDesign.starter(store);
    applyStoreBranding(
        title: store.name, faviconUrl: design.value!.theme.faviconUrl);
  }

  void _startNotifications() {
    final user = customer;
    if (user != null) Get.find<NotificationCenter>().start(user.uid);
  }

  // ---- Browser tab branding -----------------------------------------------

  var _pagesOpen = 0;

  /// Storefront pages report themselves open and closed, so the browser
  /// tab goes back to Sellora's name and icon once the visitor leaves the
  /// storefront, not when they move between its pages.
  void attach() => _pagesOpen++;

  void detach() {
    _pagesOpen--;
    // A page replacing this one has attached by the time the old one
    // unmounts.
    scheduleMicrotask(() {
      if (_pagesOpen <= 0) {
        _pagesOpen = 0;
        resetStoreBranding();
      }
    });
  }

  // ---- Links ----------------------------------------------------------------

  /// `/s/{slug}` plus [path] (`products/p1`, `cart`, `pages/refund-policy`).
  String path([String path = '']) =>
      path.isEmpty ? '/s/$slug' : '/s/$slug/$path';

  /// A category's URL segment: lower-case words joined by hyphens, so
  /// "Home & Living" is `home-living`.
  static String collectionHandle(String category) => category
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  /// The category [handle] names among this store's, if any.
  String? categoryForHandle(String handle) => categories
      .firstWhereOrNull((c) => collectionHandle(c) == handle.toLowerCase());
}
