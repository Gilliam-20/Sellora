/// Lowercases [input], replaces runs of non-alphanumeric characters with a
/// single hyphen, and trims leading/trailing hyphens — e.g. "Amina's Curated
/// Picks!" -> "aminas-curated-picks". Used to derive a store's public
/// `/s/{slug}` handle from its display name at signup.
String slugify(String input) {
  final lowered = input.toLowerCase().trim();
  // Drop apostrophes entirely (so "Amina's Store" -> "aminas-store", not
  // "amina-s-store") before hyphenating every other run of non-alphanumerics.
  final noApostrophes = lowered.replaceAll(RegExp(r"['’]"), '');
  final hyphenated = noApostrophes.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  final trimmed = hyphenated.replaceAll(RegExp(r'^-+|-+$'), '');
  return trimmed.isEmpty ? 'store' : trimmed;
}
