/// Shows a store's favicon in the browser tab while its storefront is
/// open (web only; a no-op elsewhere). The tab title follows the `Title`
/// widget the storefront wraps itself in.
library;

export 'store_branding_stub.dart'
    if (dart.library.js_interop) 'store_branding_web.dart';
