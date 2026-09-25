/// Lowercases [input], replaces runs of non-alphanumeric characters with a
/// single hyphen, and trims leading/trailing hyphens — e.g. "Amina's Curated
/// Picks!" -> "aminas-curated-picks". Used to derive a store's public
/// `/s/{slug}` handle from its display name at signup.
///
/// Capped at [maxSlugLength] so a de-duplicating `-N` suffix still fits
/// under the `stores.slug` check constraint's 80-character limit.
const maxSlugLength = 60;

String slugify(String input) {
  final lowered = input.toLowerCase().trim();
  // Drop apostrophes entirely (so "Amina's Store" -> "aminas-store", not
  // "amina-s-store") before hyphenating every other run of non-alphanumerics.
  final noApostrophes = lowered.replaceAll(RegExp(r"['’]"), '');
  final hyphenated = noApostrophes.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  final trimmed = hyphenated.replaceAll(RegExp(r'^-+|-+$'), '');
  if (trimmed.isEmpty) return 'store';
  if (trimmed.length <= maxSlugLength) return trimmed;
  // Cutting mid-word can leave a trailing hyphen, which the rules reject.
  return trimmed
      .substring(0, maxSlugLength)
      .replaceAll(RegExp(r'-+$'), '');
}
