import 'package:flutter_test/flutter_test.dart';
import 'package:sellora/core/utils/store_link.dart';

void main() {
  test('puts the storefront route in the fragment, on the page origin', () {
    final link = storefrontLink('amina-store',
        base: Uri.parse('https://sellora.web.app/#/seller/marketing?x=1'));
    expect(link.toString(), 'https://sellora.web.app/#/s/amina-store');
  });

  test('keeps a non-default port (local web runs)', () {
    final link =
        storefrontLink('shop', base: Uri.parse('http://localhost:5000/#/x'));
    expect(link.toString(), 'http://localhost:5000/#/s/shop');
  });

  test('share links carry the encoded store link', () {
    final link = Uri.parse('https://sellora.app/#/s/shop');
    final links = shareLinks(link, 'Shop with me:');
    expect(links.keys, ['WhatsApp', 'Facebook', 'X']);
    expect(links['WhatsApp']!.queryParameters['text'],
        'Shop with me: https://sellora.app/#/s/shop');
    expect(links['Facebook']!.queryParameters['u'], link.toString());
    expect(links['X']!.queryParameters['url'], link.toString());
  });
}
