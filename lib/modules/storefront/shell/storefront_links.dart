import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/models/store_design.dart';
import '../../../data/models/store_page.dart';
import '../storefront_session.dart';

/// Where each storefront page lives, under `/s/{slug}` (TODO §20).
class StorefrontPaths {
  StorefrontPaths._();

  static const shop = 'shop';
  static const search = 'search';
  static const collections = 'collections';
  static const cart = 'cart';
  static const checkout = 'checkout';
  static const account = 'account';
  static const orders = 'account/orders';
  static const notifications = 'account/notifications';
  static const login = 'login';

  static String product(String id) => 'products/${Uri.encodeComponent(id)}';
  static String order(String id) => 'orders/${Uri.encodeComponent(id)}';
  static String collection(String category) =>
      'collections/${StorefrontSession.collectionHandle(category)}';
  static String page(StorePageKind kind) => 'pages/${kind.path}';

  /// The sign-in page, coming back to [then] (a path under this store)
  /// afterwards.
  static String loginThen(String then) =>
      '$login?return=${Uri.encodeQueryComponent(then)}';

  /// [path] carrying on the current page's `?return=`, so moving between
  /// sign-in and sign-up keeps where the visitor is headed.
  static String keepReturn(String path) {
    final r = Get.parameters['return'];
    return r == null ? path : '$path?return=${Uri.encodeQueryComponent(r)}';
  }
}

/// Follows a design link from anywhere but the homepage, where some links
/// scroll instead (see StorefrontRenderer.openLink).
Future<void> openStoreLink(LinkTarget target) async {
  final session = Get.find<StorefrontSession>();
  switch (target.kind) {
    case LinkKind.home:
    case LinkKind.section:
      await Get.offAllNamed(session.path());
    case LinkKind.catalog:
      await Get.toNamed(session.path(StorefrontPaths.shop));
    case LinkKind.category:
      await Get.toNamed(session.path(StorefrontPaths.collection(target.value)));
    case LinkKind.collections:
      await Get.toNamed(session.path(StorefrontPaths.collections));
    case LinkKind.search:
      await Get.toNamed(session.path(StorefrontPaths.search));
    case LinkKind.page:
      final kind = StorePageKind.parse(target.value);
      if (kind != null) {
        await Get.toNamed(session.path(StorefrontPaths.page(kind)));
      }
    case LinkKind.url:
      await launchUrl(Uri.parse(target.value),
          mode: LaunchMode.externalApplication);
  }
}
