import 'package:flutter_test/flutter_test.dart';
import 'package:sellora/core/utils/listing_text.dart';
import 'package:sellora/data/models/product_model.dart';

void main() {
  group('ListingText.plain', () {
    test('strips CJ HTML and entities', () {
      expect(
        ListingText.plain(
            '<p>Warm&nbsp;light</p><ul><li>USB &amp; mains</li></ul><br/>Size: 20cm'),
        'Warm light USB & mains Size: 20cm',
      );
    });

    test('leaves plain text alone', () {
      expect(ListingText.plain('  A   lamp '), 'A lamp');
    });
  });

  group('ListingText.clip', () {
    test('keeps short text', () {
      expect(ListingText.clip('Desk lamp', 60), 'Desk lamp');
    });

    test('cuts at a word boundary with an ellipsis, within the limit', () {
      final clipped = ListingText.clip(
          'A very warm and bright desk lamp for reading at night', 30);
      expect(clipped.length, lessThanOrEqualTo(30));
      expect(clipped, 'A very warm and bright desk…');
    });

    test('cuts mid-word when there is no sensible space', () {
      expect(ListingText.clip('x' * 50, 10).length, 10);
    });
  });

  group('SEO suggestions', () {
    test('description falls back to the title', () {
      expect(ListingText.suggestSeoDescription('', 'Desk lamp'), 'Desk lamp');
    });

    test('stay within what search results show', () {
      final long = 'word ' * 100;
      expect(ListingText.suggestSeoTitle(long).length,
          lessThanOrEqualTo(ListingText.seoTitleTarget));
      expect(ListingText.suggestSeoDescription('<p>$long</p>', 't').length,
          lessThanOrEqualTo(ListingText.seoDescriptionTarget));
    });
  });

  group('tags', () {
    test('normalizes what was typed', () {
      expect(ListingText.normalizeTag('  #Summer   sale '), 'Summer sale');
      expect(ListingText.normalizeTag('   '), '');
      expect(ListingText.normalizeTag('a' * 60).length, ListingText.tagMax);
    });

    test('adds comma-separated tags without case-insensitive duplicates', () {
      expect(ListingText.addTags(['Summer'], 'summer, gifts, , Gifts, lamp'),
          ['Summer', 'gifts', 'lamp']);
    });

    test('stops at the limit', () {
      final many = List.generate(25, (i) => 't$i').join(',');
      expect(ListingText.addTags([], many, limit: ProductModel.maxTags).length,
          ProductModel.maxTags);
    });
  });

  test('a product round-trips its tags and SEO fields', () {
    final product = ProductModel(
      id: 'p1',
      cjProductId: 'p1',
      title: 'Lamp',
      imageUrl: '',
      costPrice: 5,
      sellPrice: 12,
      category: 'Home',
      tags: ['summer'],
      seoTitle: 'Desk lamp',
      seoDescription: 'Warm light',
    );
    final back = ProductModel.fromMap(product.toMap());
    expect(back.tags, ['summer']);
    expect(back.seoTitle, 'Desk lamp');
    expect(back.seoDescription, 'Warm light');
    final edited = product.copyWith(
        title: 'New', images: ['a', 'b'], imageUrl: 'a', tags: const []);
    expect([edited.title, edited.imageUrl, edited.images.length, edited.tags],
        ['New', 'a', 2, isEmpty]);
    expect(edited.seoTitle, 'Desk lamp');
  });
}
