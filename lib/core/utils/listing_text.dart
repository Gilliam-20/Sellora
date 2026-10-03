/// Text clean-up for the import editor's tags and SEO fields. Pure, so it's
/// unit-tested without a widget tree (test/listing_text_test.dart).
class ListingText {
  ListingText._();

  /// Search engines cut titles and descriptions off past roughly these
  /// lengths; the editor suggests within them. The database's own caps
  /// (120/320) are looser.
  static const seoTitleTarget = 60;
  static const seoDescriptionTarget = 160;
  static const seoTitleMax = 120;
  static const seoDescriptionMax = 320;
  static const tagMax = 40;

  /// CJ descriptions arrive as HTML. Strips tags and the common entities
  /// and collapses whitespace, for an SEO description or a plain preview.
  static String plain(String html) {
    return html
        .replaceAll(
            RegExp(r'<(br|/p|/div|/li)\s*/?>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// [text] cut to at most [max] characters at a word boundary, with an
  /// ellipsis when anything was dropped.
  static String clip(String text, int max) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= max) return clean;
    final cut = clean.substring(0, max - 1);
    final space = cut.lastIndexOf(' ');
    final head = space > max ~/ 2 ? cut.substring(0, space) : cut;
    return '${head.replaceAll(RegExp(r'[\s,;:.\-]+$'), '')}…';
  }

  static String suggestSeoTitle(String title) => clip(title, seoTitleTarget);

  static String suggestSeoDescription(String description, String title) {
    final body = plain(description);
    return clip(body.isNotEmpty ? body : title, seoDescriptionTarget);
  }

  /// One tag as typed, cleaned: trimmed, inner whitespace collapsed, a
  /// leading `#` dropped, capped at [tagMax]. Empty when nothing is left.
  static String normalizeTag(String raw) {
    var tag = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (tag.startsWith('#')) tag = tag.substring(1).trim();
    return tag.length > tagMax ? tag.substring(0, tagMax).trim() : tag;
  }

  /// [existing] plus whatever comma-separated tags [input] holds, without
  /// case-insensitive duplicates and never past [limit].
  static List<String> addTags(List<String> existing, String input,
      {int limit = 20}) {
    final result = [...existing];
    final seen = existing.map((t) => t.toLowerCase()).toSet();
    for (final part in input.split(',')) {
      final tag = normalizeTag(part);
      if (tag.isEmpty || seen.contains(tag.toLowerCase())) continue;
      if (result.length >= limit) break;
      result.add(tag);
      seen.add(tag.toLowerCase());
    }
    return result;
  }
}
