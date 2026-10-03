import 'store_design.dart';
import 'store_model.dart';

/// A storefront theme (TODO §19): a named, versioned starting point for a
/// [StoreDesign]. It carries the look (colors, typography and layout style,
/// all in [settings]) and a starter homepage ([sections]).
///
/// Themes are defined here, in code, not in the database: each one only
/// combines settings the renderer already understands, so a new theme
/// needs no migration and can't name anything the storefront can't draw.
/// The thumbnail is drawn from [settings] (`ThemeThumbnail`), so it always
/// matches what applying the theme does.
///
/// Applying a theme copies its settings into the store's design, which
/// then belongs to the seller. Changing the theme here later doesn't
/// change anyone's storefront; a higher [version] makes the builder offer
/// the update.
class StoreTheme {
  const StoreTheme({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.settings,
    required this.sections,
    this.suitedTo = const {},
  });

  final String id;
  final String name;

  /// Bumped whenever [settings] change, so stores styled from an older
  /// version are offered the new look.
  final int version;
  final String description;

  /// Colors, typography, buttons and layout style.
  final ThemeSettings settings;

  /// The starter homepage, filled in from the store's own details.
  final List<StoreSection> Function(StoreModel store) sections;

  /// [StoreCategories] keys this theme is suggested for.
  final Set<String> suitedTo;

  static const general = StoreTheme(
    id: 'general',
    name: 'General Store',
    version: 1,
    description: 'Sellora\'s own look: friendly serif headings, rounded '
        'cards, room for every kind of product.',
    suitedTo: {'general', 'home', 'kids', 'sports'},
    // The defaults are this theme, so designs saved before themes existed
    // read as General Store unchanged.
    settings: ThemeSettings(),
    sections: _generalSections,
  );

  static const minimal = StoreTheme(
    id: 'minimal',
    name: 'Minimal',
    version: 1,
    description: 'Black on white, square corners and plenty of space. Lets '
        'the products speak.',
    suitedTo: {'beauty', 'home'},
    settings: ThemeSettings(
      accentHex: '#14161F',
      backgroundHex: '#FFFFFF',
      surfaceHex: '#FFFFFF',
      textHex: '#14161F',
      headingFont: 'DM Sans',
      bodyFont: 'Inter',
      buttonShape: ButtonShape.square,
      corners: CornerStyle.sharp,
      cardStyle: CardStyle.flat,
      imageShape: ImageShape.square,
      spacing: SectionSpacing.airy,
      centeredHeader: true,
    ),
    sections: _minimalSections,
  );

  static const modern = StoreTheme(
    id: 'modern',
    name: 'Modern',
    version: 1,
    description: 'Bold geometric type, an indigo accent and cards that lift '
        'off the page.',
    suitedTo: {'sports'},
    settings: ThemeSettings(
      accentHex: '#4F46E5',
      backgroundHex: '#F6F7FB',
      surfaceHex: '#FFFFFF',
      textHex: '#111827',
      headingFont: 'Space Grotesk',
      bodyFont: 'Inter',
      buttonShape: ButtonShape.rounded,
      corners: CornerStyle.round,
      cardStyle: CardStyle.raised,
      imageShape: ImageShape.square,
      spacing: SectionSpacing.comfortable,
    ),
    sections: _modernSections,
  );

  static const fashion = StoreTheme(
    id: 'fashion',
    name: 'Fashion',
    version: 1,
    description: 'Editorial serif headings, tall product photos and a warm '
        'cream page, like a lookbook.',
    suitedTo: {'fashion', 'beauty'},
    settings: ThemeSettings(
      accentHex: '#1F1A17',
      backgroundHex: '#FAF7F2',
      surfaceHex: '#FAF7F2',
      textHex: '#1F1A17',
      headingFont: 'Playfair Display',
      bodyFont: 'Montserrat',
      buttonShape: ButtonShape.square,
      corners: CornerStyle.sharp,
      cardStyle: CardStyle.flat,
      imageShape: ImageShape.portrait,
      spacing: SectionSpacing.airy,
      centeredHeader: true,
      uppercaseHeadings: true,
    ),
    sections: _fashionSections,
  );

  static const electronics = StoreTheme(
    id: 'electronics',
    name: 'Electronics',
    version: 1,
    description: 'Crisp and dense: outlined cards, a tech blue accent and '
        'more products per screen.',
    suitedTo: {'electronics'},
    settings: ThemeSettings(
      accentHex: '#1565C0',
      backgroundHex: '#F3F5F8',
      surfaceHex: '#FFFFFF',
      textHex: '#0F172A',
      headingFont: 'Montserrat',
      bodyFont: 'Inter',
      buttonShape: ButtonShape.rounded,
      corners: CornerStyle.soft,
      cardStyle: CardStyle.outlined,
      imageShape: ImageShape.square,
      spacing: SectionSpacing.compact,
    ),
    sections: _electronicsSections,
  );

  /// In the order the builder shows them.
  static const all = [general, minimal, modern, fashion, electronics];

  /// Designs saved before themes existed say `meridian`.
  static const _aliases = {'meridian': 'general'};

  /// The theme [id] names, or General Store for an unknown id (a theme
  /// that was removed, or a hand-written document).
  static StoreTheme byId(String id) {
    final key = _aliases[id] ?? id;
    return all.firstWhere((t) => t.id == key, orElse: () => general);
  }

  /// The theme to suggest for a store of [category] (a [StoreCategories]
  /// key).
  static StoreTheme suggestedFor(String? category) =>
      all.firstWhere((t) => t.id != general.id && t.suitedTo.contains(category),
          orElse: () => general);

  /// [design] restyled with this theme. Its content (announcement, menu,
  /// footer, favicon) stays; its homepage is replaced by this theme's only
  /// when [homepage] is set.
  StoreDesign applyTo(StoreDesign design,
          {required StoreModel store, bool homepage = false}) =>
      design.copyWith(
        themeId: id,
        themeVersion: version,
        theme: settings.copyWith(faviconUrl: design.theme.faviconUrl),
        sections: homepage ? sections(store) : null,
      );

  /// Whether [design] was styled from an older version of its theme.
  static bool hasUpdate(StoreDesign design) =>
      design.themeVersion < byId(design.themeId).version;
}

// ---------------------------------------------------------------------------
// Starter homepages. They hold only the store's own words and photos, or
// neutral placeholders the seller edits: no made-up reviews, offers or
// delivery promises.
// ---------------------------------------------------------------------------

String? _banner(StoreModel store) {
  final url = store.bannerUrl;
  return url != null && url.startsWith('http') ? url : null;
}

StoreSection _hero(StoreModel store, Map<String, Object?> settings) =>
    StoreSection.create(SectionType.hero, settings: {
      'heading': store.name,
      'subheading': store.tagline ?? '',
      if (_banner(store) case final url?) 'imageUrl': url,
      ...settings,
    });

StoreSection _featured(String title, String source, String count) =>
    StoreSection.create(SectionType.featuredProducts,
        settings: {'title': title, 'source': source, 'count': count});

StoreSection _catalog([String title = 'All products']) =>
    StoreSection.create(SectionType.catalog, settings: {'title': title});

StoreSection _story(StoreModel store, {String alignment = 'center'}) =>
    StoreSection.create(SectionType.richText, settings: {
      'heading': 'About ${store.name}',
      'body': store.tagline ?? '',
      'alignment': alignment,
    });

List<StoreSection> _generalSections(StoreModel store) => [
      _hero(store, {}),
      _featured('New in', 'newest', '4'),
      _catalog(),
    ];

List<StoreSection> _minimalSections(StoreModel store) => [
      StoreSection.create(SectionType.richText, settings: {
        'heading': store.name,
        'body': store.tagline ?? '',
        'alignment': 'center',
      }),
      _featured('Featured', 'newest', '4'),
      _catalog('Shop'),
    ];

List<StoreSection> _modernSections(StoreModel store) => [
      _hero(store, {'alignment': 'center', 'height': 'large'}),
      _featured('Best sellers', 'bestSelling', '8'),
      _story(store),
      StoreSection.create(SectionType.newsletter),
      _catalog(),
    ];

List<StoreSection> _fashionSections(StoreModel store) => [
      _hero(store, {
        'alignment': 'center',
        'height': 'large',
        'buttonLabel': 'Shop the collection',
      }),
      _featured('New in', 'newest', '8'),
      _story(store),
      StoreSection.create(SectionType.newsletter, settings: {
        'heading': 'Join the list',
        'text': 'Be first to hear about new pieces.',
      }),
      _catalog('Shop all'),
    ];

List<StoreSection> _electronicsSections(StoreModel store) => [
      _hero(store, {'height': 'small'}),
      _featured('Best sellers', 'bestSelling', '8'),
      _featured('Just in', 'newest', '4'),
      _catalog('All products'),
    ];
