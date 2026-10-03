import 'package:web/web.dart' as web;

/// Sellora's own icon, restored when the storefront closes.
String? _defaultIcon;

web.HTMLLinkElement? _iconLink() =>
    web.document.querySelector('link[rel="icon"]') as web.HTMLLinkElement?;

void applyStoreBranding({required String title, String? faviconUrl}) {
  final link = _iconLink();
  if (link == null) return;
  _defaultIcon ??= link.href;
  link.href = faviconUrl ?? _defaultIcon!;
}

void resetStoreBranding() {
  final link = _iconLink();
  if (link != null && _defaultIcon != null) link.href = _defaultIcon!;
}
