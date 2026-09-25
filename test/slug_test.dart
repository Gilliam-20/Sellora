import 'package:flutter_test/flutter_test.dart';
import 'package:sellora/core/utils/slug.dart';

/// Mirrors firestore.rules' `isValidSlug`: a store whose slug fails it
/// can't be created, so slugify must never produce one.
final _validSlug = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

void main() {
  test('derives a hyphenated handle from a display name', () {
    expect(slugify("Amina's Curated Picks!"), 'aminas-curated-picks');
    expect(slugify('  !!!  '), 'store');
  });

  test('caps long names and never ends on a hyphen', () {
    final slug = slugify('${'a' * 59} ${'b' * 30}');
    expect(slug.length, lessThanOrEqualTo(maxSlugLength));
    expect(slug, 'a' * 59);
    expect(_validSlug.hasMatch(slug), isTrue);
  });

  test('always satisfies the rules-side slug pattern', () {
    for (final name in [
      'Nairobi Threads',
      '---Weird---Name---',
      'Ümlaut Café & Co.',
      'x' * 200,
      '42',
    ]) {
      final slug = slugify(name);
      expect(_validSlug.hasMatch(slug), isTrue, reason: '$name -> $slug');
      // Leaves room for the `-N` de-duplication suffix under the 80 cap.
      expect(slug.length, lessThanOrEqualTo(maxSlugLength));
    }
  });
}
