import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';

/// The public address of a store's storefront. Routing is hash-based (no
/// `usePathUrlStrategy()`), so the route goes in the fragment. On web it's
/// the page's own origin; elsewhere [AppConstants.webAppUrl].
Uri storefrontLink(String slug, {Uri? base}) {
  final origin =
      base ?? (kIsWeb ? Uri.base : Uri.parse(AppConstants.webAppUrl));
  return Uri(
    scheme: origin.scheme,
    host: origin.host,
    port: origin.hasPort ? origin.port : null,
    path: '/',
    fragment: '/s/$slug',
  );
}

/// Ready-made "share this" links for a storefront: each opens the network's
/// own share dialog with [message] and [link] filled in.
Map<String, Uri> shareLinks(Uri link, String message) => {
      'WhatsApp': Uri.https('wa.me', '/', {'text': '$message $link'}),
      'Facebook': Uri.https(
          'www.facebook.com', '/sharer/sharer.php', {'u': link.toString()}),
      'X': Uri.https('twitter.com', '/intent/tweet',
          {'text': message, 'url': link.toString()}),
    };
