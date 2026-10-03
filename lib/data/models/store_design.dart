import 'store_model.dart';
import 'store_page.dart';

/// A storefront's design (TODO §18): Store → Theme → Sections → Blocks →
/// Settings. One document per store, stored as JSON in `store_designs`
/// (a draft the seller edits, and the published copy buyers see).
///
/// Everything a seller can configure is described by a schema
/// ([SectionType.settings], [BlockSchema.settings]), so the builder's
/// editor and the storefront renderer are both generic over section types:
/// adding a section type is a schema plus a renderer widget.
///
/// Reading is defensive. The document comes from JSON a client wrote, so
/// unknown section types are dropped, unknown fonts fall back to the
/// default, and a link that isn't http(s) is treated as no link.
class StoreDesign {
  const StoreDesign({
    this.themeId = defaultThemeId,
    this.themeVersion = 1,
    this.theme = const ThemeSettings(),
    this.announcement = const AnnouncementBar(),
    this.navigation = const [],
    required this.sections,
    this.footer = const FooterSettings(),
  });

  static const schemaVersion = 1;
  static const defaultThemeId = 'general';
  static const maxSections = 40;
  static const maxNavLinks = 8;

  /// The theme this design was last styled from (`StoreTheme.byId`), and
  /// that theme's version then, so the builder can offer its updates.
  final String themeId;
  final int themeVersion;
  final ThemeSettings theme;
  final AnnouncementBar announcement;
  final List<StoreLink> navigation;

  /// The homepage, top to bottom.
  final List<StoreSection> sections;
  final FooterSettings footer;

  /// What a store gets before its seller designs anything: today's
  /// storefront (banner, then the catalog) expressed as sections, using the
  /// branding the store already has.
  factory StoreDesign.starter(StoreModel store) {
    return StoreDesign(
      theme: ThemeSettings(
          accentHex:
              _validHex(store.primaryColorHex) ?? ThemeSettings.defaultAccent),
      navigation: const [
        StoreLink(label: 'Home', target: LinkTarget.home),
        StoreLink(label: 'Shop all', target: LinkTarget.catalog),
      ],
      sections: [
        StoreSection.create(SectionType.hero, id: 'hero', settings: {
          'heading': store.name,
          'subheading': store.tagline ?? '',
          if (store.bannerUrl != null && store.bannerUrl!.startsWith('http'))
            'imageUrl': store.bannerUrl,
        }),
        StoreSection.create(SectionType.catalog, id: 'catalog'),
      ],
      footer: FooterSettings(aboutText: store.tagline ?? ''),
    );
  }

  StoreDesign copyWith({
    String? themeId,
    int? themeVersion,
    ThemeSettings? theme,
    AnnouncementBar? announcement,
    List<StoreLink>? navigation,
    List<StoreSection>? sections,
    FooterSettings? footer,
  }) =>
      StoreDesign(
        themeId: themeId ?? this.themeId,
        themeVersion: themeVersion ?? this.themeVersion,
        theme: theme ?? this.theme,
        announcement: announcement ?? this.announcement,
        navigation: navigation ?? this.navigation,
        sections: sections ?? this.sections,
        footer: footer ?? this.footer,
      );

  StoreSection? sectionById(String id) =>
      sections.where((s) => s.id == id).firstOrNull;

  /// Replaces the section with [section]'s id.
  StoreDesign withSection(StoreSection section) => copyWith(
      sections: [for (final s in sections) s.id == section.id ? section : s]);

  /// Why this can't be published, or empty when it can. The database
  /// checks only the size and section count; the rest is here.
  List<String> problems() {
    final out = <String>[];
    if (sections.isEmpty) out.add('Add at least one section to the homepage.');
    if (sections.length > maxSections) {
      out.add('A homepage can have at most $maxSections sections.');
    }
    if (!sections.any((s) => s.type == SectionType.catalog && s.enabled)) {
      out.add('Keep the "All products" section visible so buyers can browse '
          'your catalog.');
    }
    for (final section in sections) {
      for (final p in section.problems()) {
        out.add('${section.title}: $p');
      }
    }
    if (announcement.enabled && announcement.text.trim().isEmpty) {
      out.add('Announcement bar: add some text, or turn it off.');
    }
    for (final link in [...navigation, ...footer.links]) {
      if (link.label.trim().isEmpty) out.add('Every menu link needs a label.');
    }
    return out;
  }

  factory StoreDesign.fromMap(Map<String, dynamic> map) {
    final sections = <StoreSection>[];
    for (final raw in _list(map['sections'])) {
      final section = StoreSection.tryFromMap(_map(raw));
      // Two catalogs, or a duplicated id, would confuse the renderer.
      if (section == null ||
          sections.any((s) => s.id == section.id) ||
          (section.type.isSingleton &&
              sections.any((s) => s.type == section.type))) {
        continue;
      }
      sections.add(section);
    }
    return StoreDesign(
      themeId: switch (map['themeId']) {
        final String id when id.isNotEmpty => _clip(id, 40),
        _ => defaultThemeId,
      },
      themeVersion: switch (map['themeVersion']) {
        final int v when v > 0 => v,
        _ => 1,
      },
      theme: ThemeSettings.fromMap(_map(map['theme'])),
      announcement: AnnouncementBar.fromMap(_map(map['announcement'])),
      navigation: _links(map['navigation'], maxNavLinks),
      sections: sections.take(maxSections).toList(),
      footer: FooterSettings.fromMap(_map(map['footer'])),
    );
  }

  Map<String, dynamic> toMap() => {
        'schemaVersion': schemaVersion,
        'themeId': themeId,
        'themeVersion': themeVersion,
        'theme': theme.toMap(),
        'announcement': announcement.toMap(),
        'navigation': [for (final l in navigation) l.toMap()],
        'sections': [for (final s in sections) s.toMap()],
        'footer': footer.toMap(),
      };
}

// ---------------------------------------------------------------------------
// Theme settings
// ---------------------------------------------------------------------------

enum ButtonShape {
  pill('pill', 'Pill'),
  rounded('rounded', 'Rounded'),
  square('square', 'Square');

  const ButtonShape(this.id, this.label);
  final String id;
  final String label;

  static ButtonShape parse(Object? id) =>
      values.firstWhere((v) => v.id == id, orElse: () => pill);
}

/// A Google Font a storefront may use. Only these are accepted, so a
/// design can't name a family the renderer can't load.
class StoreFont {
  const StoreFont(this.family, this.style);
  final String family;

  /// 'serif', 'sans' or 'display', shown in the picker.
  final String style;

  static const all = [
    StoreFont('Fraunces', 'serif'),
    StoreFont('Playfair Display', 'serif'),
    StoreFont('Lora', 'serif'),
    StoreFont('DM Serif Display', 'serif'),
    StoreFont('Inter', 'sans'),
    StoreFont('Poppins', 'sans'),
    StoreFont('Montserrat', 'sans'),
    StoreFont('DM Sans', 'sans'),
    StoreFont('Space Grotesk', 'display'),
    StoreFont('Bebas Neue', 'display'),
  ];

  static String valid(Object? family, String fallback) =>
      all.any((f) => f.family == family) ? family as String : fallback;
}

/// How rounded cards, images and panels are (buttons have [ButtonShape]).
enum CornerStyle {
  sharp('sharp', 'Square', 0, 0),
  soft('soft', 'Soft', 8, 4),
  round('round', 'Rounded', 18, 6);

  const CornerStyle(this.id, this.label, this.large, this.small);
  final String id;
  final String label;

  /// Cards, banners and panels.
  final double large;

  /// Collection tiles and quotes.
  final double small;

  static CornerStyle parse(Object? id) =>
      values.firstWhere((v) => v.id == id, orElse: () => round);
}

/// How product cards and panels sit on the page.
enum CardStyle {
  flat('flat', 'Flat'),
  outlined('outlined', 'Outlined'),
  raised('raised', 'Shadow');

  const CardStyle(this.id, this.label);
  final String id;
  final String label;

  static CardStyle parse(Object? id) =>
      values.firstWhere((v) => v.id == id, orElse: () => flat);
}

/// The shape of product photos in grids, as width / height.
enum ImageShape {
  square('square', 'Square', 1),
  portrait('portrait', 'Portrait', 3 / 4),
  landscape('landscape', 'Landscape', 4 / 3);

  const ImageShape(this.id, this.label, this.aspectRatio);
  final String id;
  final String label;
  final double aspectRatio;

  static ImageShape parse(Object? id) =>
      values.firstWhere((v) => v.id == id, orElse: () => square);
}

/// The vertical gap between homepage sections.
enum SectionSpacing {
  compact('compact', 'Compact', 16),
  comfortable('comfortable', 'Comfortable', 24),
  airy('airy', 'Airy', 48);

  const SectionSpacing(this.id, this.label, this.gap);
  final String id;
  final String label;
  final double gap;

  static SectionSpacing parse(Object? id) =>
      values.firstWhere((v) => v.id == id, orElse: () => comfortable);
}

class ThemeSettings {
  const ThemeSettings({
    this.accentHex = defaultAccent,
    this.backgroundHex = '#FCFCFB',
    this.surfaceHex = '#FCFCFB',
    this.textHex = '#14161F',
    this.headingFont = 'Fraunces',
    this.bodyFont = 'Inter',
    this.buttonShape = ButtonShape.pill,
    this.corners = CornerStyle.round,
    this.cardStyle = CardStyle.flat,
    this.imageShape = ImageShape.square,
    this.spacing = SectionSpacing.comfortable,
    this.centeredHeader = false,
    this.uppercaseHeadings = false,
    this.faviconUrl,
  });

  /// Cargo Navy, the Meridian default.
  static const defaultAccent = '#303F9F';

  final String accentHex;
  final String backgroundHex;

  /// Product cards, quotes, inputs: whatever sits on the background.
  final String surfaceHex;
  final String textHex;
  final String headingFont;
  final String bodyFont;
  final ButtonShape buttonShape;
  final CornerStyle corners;
  final CardStyle cardStyle;
  final ImageShape imageShape;
  final SectionSpacing spacing;

  /// The store name centered in the header, rather than at the start.
  final bool centeredHeader;

  /// Section titles in capitals, letter-spaced.
  final bool uppercaseHeadings;

  /// Shown in the browser tab on the web storefront.
  final String? faviconUrl;

  ThemeSettings copyWith({
    String? accentHex,
    String? backgroundHex,
    String? surfaceHex,
    String? textHex,
    String? headingFont,
    String? bodyFont,
    ButtonShape? buttonShape,
    CornerStyle? corners,
    CardStyle? cardStyle,
    ImageShape? imageShape,
    SectionSpacing? spacing,
    bool? centeredHeader,
    bool? uppercaseHeadings,
    String? faviconUrl,
    bool clearFavicon = false,
  }) =>
      ThemeSettings(
        accentHex: accentHex ?? this.accentHex,
        backgroundHex: backgroundHex ?? this.backgroundHex,
        surfaceHex: surfaceHex ?? this.surfaceHex,
        textHex: textHex ?? this.textHex,
        headingFont: headingFont ?? this.headingFont,
        bodyFont: bodyFont ?? this.bodyFont,
        buttonShape: buttonShape ?? this.buttonShape,
        corners: corners ?? this.corners,
        cardStyle: cardStyle ?? this.cardStyle,
        imageShape: imageShape ?? this.imageShape,
        spacing: spacing ?? this.spacing,
        centeredHeader: centeredHeader ?? this.centeredHeader,
        uppercaseHeadings: uppercaseHeadings ?? this.uppercaseHeadings,
        faviconUrl: clearFavicon ? null : faviconUrl ?? this.faviconUrl,
      );

  /// A document saved before themes (TODO §19) has no surface or style,
  /// and reads as today's look: surface = background, the defaults.
  factory ThemeSettings.fromMap(Map<String, dynamic> map) {
    final colors = _map(map['colors']);
    final type = _map(map['typography']);
    final style = _map(map['style']);
    const d = ThemeSettings();
    final background = _validHex(colors['background']) ?? d.backgroundHex;
    return ThemeSettings(
      accentHex: _validHex(colors['accent']) ?? d.accentHex,
      backgroundHex: background,
      surfaceHex: _validHex(colors['surface']) ?? background,
      textHex: _validHex(colors['text']) ?? d.textHex,
      headingFont: StoreFont.valid(type['heading'], d.headingFont),
      bodyFont: StoreFont.valid(type['body'], d.bodyFont),
      buttonShape: ButtonShape.parse(map['buttonShape']),
      corners: CornerStyle.parse(style['corners']),
      cardStyle: CardStyle.parse(style['cards']),
      imageShape: ImageShape.parse(style['productImage']),
      spacing: SectionSpacing.parse(style['spacing']),
      centeredHeader: style['header'] == 'center',
      uppercaseHeadings: style['uppercaseHeadings'] == true,
      faviconUrl: safeUrl(map['faviconUrl']),
    );
  }

  /// Nested the way `publish_store_design` reads the accent
  /// (`theme.colors.accent`).
  Map<String, dynamic> toMap() => {
        'colors': {
          'accent': accentHex,
          'background': backgroundHex,
          'surface': surfaceHex,
          'text': textHex,
        },
        'typography': {'heading': headingFont, 'body': bodyFont},
        'buttonShape': buttonShape.id,
        'style': {
          'corners': corners.id,
          'cards': cardStyle.id,
          'productImage': imageShape.id,
          'spacing': spacing.id,
          'header': centeredHeader ? 'center' : 'left',
          'uppercaseHeadings': uppercaseHeadings,
        },
        'faviconUrl': faviconUrl,
      };
}

/// Ready-made color sets for the theme editor.
class ThemePalette {
  const ThemePalette(
      this.name, this.accent, this.background, this.surface, this.text);
  final String name;
  final String accent;
  final String background;
  final String surface;
  final String text;

  static const all = [
    ThemePalette('Meridian', '#303F9F', '#FCFCFB', '#FCFCFB', '#14161F'),
    ThemePalette('Ink', '#14161F', '#FFFFFF', '#FFFFFF', '#14161F'),
    ThemePalette('Terracotta', '#C0573E', '#FBF6F1', '#FFFFFF', '#2B1D16'),
    ThemePalette('Forest', '#2F6B4F', '#F5F8F4', '#FFFFFF', '#15231B'),
    ThemePalette('Ocean', '#1F9E92', '#F3FAF9', '#FFFFFF', '#102624'),
    ThemePalette('Midnight', '#FFC107', '#14161F', '#1F2230', '#F1F3F2'),
  ];
}

// ---------------------------------------------------------------------------
// Links
// ---------------------------------------------------------------------------

enum LinkKind {
  home,
  catalog,
  category,
  section,
  url,
  collections,
  search,
  page
}

/// Where a button or menu item goes. Serialized as one string:
/// `home`, `catalog`, `category:Fashion`, `section:<id>`,
/// `url:https://...`, or (TODO §20) one of the storefront's own pages:
/// `collections`, `search`, `page:refund`.
class LinkTarget {
  const LinkTarget._(this.kind, [this.value = '']);

  static const home = LinkTarget._(LinkKind.home);
  static const catalog = LinkTarget._(LinkKind.catalog);
  static const collections = LinkTarget._(LinkKind.collections);
  static const search = LinkTarget._(LinkKind.search);
  factory LinkTarget.page(StorePageKind page) =>
      LinkTarget._(LinkKind.page, page.id);
  factory LinkTarget.category(String name) =>
      LinkTarget._(LinkKind.category, name.trim());
  factory LinkTarget.section(String id) => LinkTarget._(LinkKind.section, id);

  /// Null unless [url] is an absolute http(s) URL: anything else (a
  /// `javascript:` URL above all) must never reach the browser.
  static LinkTarget? url(String url) {
    final safe = safeUrl(url);
    return safe == null ? null : LinkTarget._(LinkKind.url, safe);
  }

  final LinkKind kind;
  final String value;

  static LinkTarget? parse(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    final i = raw.indexOf(':');
    final head = i < 0 ? raw : raw.substring(0, i);
    final rest = i < 0 ? '' : raw.substring(i + 1);
    return switch (head) {
      'home' => home,
      'catalog' => catalog,
      'collections' => collections,
      'search' => search,
      'page' when StorePageKind.parse(rest) != null =>
        LinkTarget.page(StorePageKind.parse(rest)!),
      'category' when rest.trim().isNotEmpty => LinkTarget.category(rest),
      'section' when rest.isNotEmpty => LinkTarget.section(rest),
      'url' => url(rest),
      _ => null,
    };
  }

  String serialize() => value.isEmpty ? kind.name : '${kind.name}:$value';

  /// For the editor: "Shop all", "Category: Fashion", the URL...
  String get describe => switch (kind) {
        LinkKind.home => 'Home',
        LinkKind.catalog => 'All products',
        LinkKind.category => 'Category: $value',
        LinkKind.section => 'A section on this page',
        LinkKind.url => value,
        LinkKind.collections => 'Collections page',
        LinkKind.search => 'Search page',
        LinkKind.page =>
          StorePageKind.parse(value)?.defaultTitle ?? 'A store page',
      };

  @override
  bool operator ==(Object other) =>
      other is LinkTarget && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

class StoreLink {
  const StoreLink({required this.label, required this.target});
  final String label;
  final LinkTarget target;

  static StoreLink? tryFromMap(Map<String, dynamic> map) {
    final target = LinkTarget.parse(map['target']);
    if (target == null) return null;
    return StoreLink(label: _clip(map['label'], 40), target: target);
  }

  Map<String, dynamic> toMap() =>
      {'label': label, 'target': target.serialize()};
}

// ---------------------------------------------------------------------------
// Announcement bar and footer
// ---------------------------------------------------------------------------

class AnnouncementBar {
  const AnnouncementBar({this.enabled = false, this.text = '', this.link});
  final bool enabled;
  final String text;
  final LinkTarget? link;

  static const maxText = 120;

  AnnouncementBar copyWith(
          {bool? enabled,
          String? text,
          LinkTarget? link,
          bool clearLink = false}) =>
      AnnouncementBar(
        enabled: enabled ?? this.enabled,
        text: text ?? this.text,
        link: clearLink ? null : link ?? this.link,
      );

  factory AnnouncementBar.fromMap(Map<String, dynamic> map) => AnnouncementBar(
        enabled: map['enabled'] == true,
        text: _clip(map['text'], maxText),
        link: LinkTarget.parse(map['link']),
      );

  Map<String, dynamic> toMap() =>
      {'enabled': enabled, 'text': text, 'link': link?.serialize()};
}

enum SocialNetwork {
  instagram('Instagram', 'instagram.com'),
  facebook('Facebook', 'facebook.com'),
  tiktok('TikTok', 'tiktok.com'),
  x('X', 'x.com'),
  youtube('YouTube', 'youtube.com'),
  whatsapp('WhatsApp', 'wa.me');

  const SocialNetwork(this.label, this.domain);
  final String label;

  /// The site a profile link is expected on, shown as a hint.
  final String domain;
}

class FooterSettings {
  const FooterSettings({
    this.aboutText = '',
    this.links = const [],
    this.social = const {},
    this.showPoweredBy = true,
  });

  static const maxAbout = 300;
  static const maxLinks = 8;

  final String aboutText;
  final List<StoreLink> links;

  /// Profile URLs, http(s) only.
  final Map<SocialNetwork, String> social;
  final bool showPoweredBy;

  FooterSettings copyWith({
    String? aboutText,
    List<StoreLink>? links,
    Map<SocialNetwork, String>? social,
    bool? showPoweredBy,
  }) =>
      FooterSettings(
        aboutText: aboutText ?? this.aboutText,
        links: links ?? this.links,
        social: social ?? this.social,
        showPoweredBy: showPoweredBy ?? this.showPoweredBy,
      );

  factory FooterSettings.fromMap(Map<String, dynamic> map) {
    final social = <SocialNetwork, String>{};
    final raw = _map(map['social']);
    for (final network in SocialNetwork.values) {
      final url = safeUrl(raw[network.name]);
      if (url != null) social[network] = url;
    }
    return FooterSettings(
      aboutText: _clip(map['aboutText'], maxAbout),
      links: _links(map['links'], maxLinks),
      social: social,
      showPoweredBy: map['showPoweredBy'] != false,
    );
  }

  Map<String, dynamic> toMap() => {
        'aboutText': aboutText,
        'links': [for (final l in links) l.toMap()],
        'social': {for (final e in social.entries) e.key.name: e.value},
        'showPoweredBy': showPoweredBy,
      };
}

// ---------------------------------------------------------------------------
// Settings schema
// ---------------------------------------------------------------------------

enum SettingKind { text, textarea, image, select, toggle, link, products }

/// One configurable field of a section or block. [visibleWhen] hides a
/// field unless another setting has a given value (e.g. the product picker
/// only when the source is "selected").
class SettingDef {
  const SettingDef(
    this.key,
    this.label,
    this.kind, {
    this.defaultValue,
    this.maxLength,
    this.options = const {},
    this.hint,
    this.required = false,
    this.visibleWhen,
  });

  final String key;
  final String label;
  final SettingKind kind;
  final Object? defaultValue;
  final int? maxLength;

  /// select: stored value → label.
  final Map<String, String> options;
  final String? hint;
  final bool required;
  final (String, Object)? visibleWhen;

  bool isVisible(Map<String, Object?> values) {
    final rule = visibleWhen;
    return rule == null || values[rule.$1] == rule.$2;
  }

  /// Coerces a stored value to this field's type, falling back to the
  /// default for anything that doesn't fit.
  Object? read(Object? raw) {
    switch (kind) {
      case SettingKind.text:
      case SettingKind.textarea:
        return raw is String ? _clip(raw, maxLength ?? 500) : defaultValue;
      case SettingKind.image:
        return safeUrl(raw) ?? defaultValue;
      case SettingKind.select:
        return options.containsKey(raw) ? raw : defaultValue;
      case SettingKind.toggle:
        return raw is bool ? raw : defaultValue;
      case SettingKind.link:
        return (LinkTarget.parse(raw) ?? LinkTarget.parse(defaultValue))
            ?.serialize();
      case SettingKind.products:
        return raw is List
            ? raw.whereType<String>().take(maxProducts).toList()
            : const <String>[];
    }
  }

  static const maxProducts = 12;
}

class BlockSchema {
  const BlockSchema({
    required this.type,
    required this.label,
    required this.settings,
    required this.max,
    this.min = 0,
    this.titleKey,
  });

  final String type;
  final String label;
  final List<SettingDef> settings;
  final int max;
  final int min;

  /// The setting shown as the block's name in the editor's list.
  final String? titleKey;
}

enum SectionType {
  hero(
    'hero',
    'Hero',
    'A large image with a headline and a button.',
    settings: [
      SettingDef('imageUrl', 'Image', SettingKind.image,
          hint: 'Wide images work best, about 1600×700.'),
      SettingDef('heading', 'Heading', SettingKind.text,
          maxLength: 80, defaultValue: 'Welcome to our store'),
      SettingDef('subheading', 'Text', SettingKind.textarea,
          maxLength: 200, defaultValue: ''),
      SettingDef('buttonLabel', 'Button label', SettingKind.text,
          maxLength: 30, defaultValue: 'Shop now'),
      SettingDef('buttonLink', 'Button link', SettingKind.link,
          defaultValue: 'catalog'),
      SettingDef('alignment', 'Text alignment', SettingKind.select,
          options: {'left': 'Left', 'center': 'Center'}, defaultValue: 'left'),
      SettingDef('height', 'Height', SettingKind.select,
          options: {'small': 'Small', 'medium': 'Medium', 'large': 'Large'},
          defaultValue: 'medium'),
    ],
  ),
  featuredProducts(
    'featuredProducts',
    'Featured products',
    'A row of products you pick, your newest, or your best sellers.',
    settings: [
      SettingDef('title', 'Title', SettingKind.text,
          maxLength: 60, defaultValue: 'Featured'),
      SettingDef('source', 'Show', SettingKind.select,
          options: {
            'newest': 'Newest products',
            'bestSelling': 'Best sellers',
            'selected': 'Products I choose',
          },
          defaultValue: 'newest'),
      SettingDef('productIds', 'Products', SettingKind.products,
          visibleWhen: ('source', 'selected')),
      SettingDef('count', 'How many', SettingKind.select,
          options: {'4': '4', '8': '8', '12': '12'}, defaultValue: '4'),
    ],
  ),
  catalog(
    'catalog',
    'All products',
    'Your full catalog with search and category filters.',
    isSingleton: true,
    settings: [
      SettingDef('title', 'Title', SettingKind.text,
          maxLength: 60, defaultValue: 'All products'),
      SettingDef('showSearch', 'Show search', SettingKind.toggle,
          defaultValue: true),
      SettingDef('showCategories', 'Show category filters', SettingKind.toggle,
          defaultValue: true),
    ],
  ),
  collectionList(
    'collectionList',
    'Collections',
    'Tiles that open a category of your catalog.',
    settings: [
      SettingDef('title', 'Title', SettingKind.text,
          maxLength: 60, defaultValue: 'Shop by collection'),
    ],
    blocks: BlockSchema(
      type: 'collection',
      label: 'Collection',
      max: 8,
      min: 1,
      titleKey: 'label',
      settings: [
        SettingDef('category', 'Category', SettingKind.text,
            maxLength: 40,
            required: true,
            hint: 'The product category it opens, e.g. Fashion'),
        SettingDef('label', 'Label', SettingKind.text,
            maxLength: 40, hint: 'Defaults to the category'),
        SettingDef('imageUrl', 'Image', SettingKind.image),
      ],
    ),
  ),
  imageBanner(
    'imageBanner',
    'Banners',
    'One to three promotional banners side by side.',
    settings: [],
    blocks: BlockSchema(
      type: 'banner',
      label: 'Banner',
      max: 3,
      min: 1,
      titleKey: 'heading',
      settings: [
        SettingDef('imageUrl', 'Image', SettingKind.image),
        SettingDef('heading', 'Heading', SettingKind.text,
            maxLength: 60, defaultValue: 'New arrivals'),
        SettingDef('text', 'Text', SettingKind.textarea,
            maxLength: 160, defaultValue: ''),
        SettingDef('buttonLabel', 'Button label', SettingKind.text,
            maxLength: 30, defaultValue: ''),
        SettingDef('link', 'Link', SettingKind.link, defaultValue: 'catalog'),
      ],
    ),
  ),
  testimonials(
    'testimonials',
    'Testimonials',
    'What your customers say about you.',
    settings: [
      SettingDef('title', 'Title', SettingKind.text,
          maxLength: 60, defaultValue: 'What customers say'),
    ],
    blocks: BlockSchema(
      type: 'testimonial',
      label: 'Testimonial',
      max: 6,
      min: 1,
      titleKey: 'author',
      settings: [
        SettingDef('quote', 'Quote', SettingKind.textarea,
            maxLength: 300, required: true),
        SettingDef('author', 'Name', SettingKind.text,
            maxLength: 60, defaultValue: ''),
        SettingDef('rating', 'Rating', SettingKind.select,
            options: {
              '0': 'No stars',
              '3': '3 stars',
              '4': '4 stars',
              '5': '5 stars',
            },
            defaultValue: '5'),
      ],
    ),
  ),
  newsletter(
    'newsletter',
    'Newsletter',
    'Collect email addresses from visitors.',
    isSingleton: true,
    settings: [
      SettingDef('heading', 'Heading', SettingKind.text,
          maxLength: 60, defaultValue: 'Join our newsletter'),
      SettingDef('text', 'Text', SettingKind.textarea,
          maxLength: 200,
          defaultValue: 'New arrivals and offers, straight to your inbox.'),
      SettingDef('buttonLabel', 'Button label', SettingKind.text,
          maxLength: 30, defaultValue: 'Subscribe'),
    ],
  ),
  richText(
    'richText',
    'Text',
    'A heading and a paragraph, e.g. your story.',
    settings: [
      SettingDef('heading', 'Heading', SettingKind.text,
          maxLength: 80, defaultValue: 'About us'),
      SettingDef('body', 'Text', SettingKind.textarea,
          maxLength: 1000, defaultValue: ''),
      SettingDef('alignment', 'Alignment', SettingKind.select,
          options: {'left': 'Left', 'center': 'Center'},
          defaultValue: 'center'),
    ],
  );

  const SectionType(
    this.id,
    this.label,
    this.description, {
    required this.settings,
    this.blocks,
    this.isSingleton = false,
  });

  final String id;
  final String label;
  final String description;
  final List<SettingDef> settings;
  final BlockSchema? blocks;

  /// At most one per homepage.
  final bool isSingleton;

  static SectionType? parse(Object? id) =>
      values.where((t) => t.id == id).firstOrNull;
}

// ---------------------------------------------------------------------------
// Sections and blocks
// ---------------------------------------------------------------------------

class SectionBlock {
  const SectionBlock(
      {required this.id, required this.type, this.settings = const {}});
  final String id;
  final String type;
  final Map<String, Object?> settings;

  SectionBlock copyWith({Map<String, Object?>? settings}) =>
      SectionBlock(id: id, type: type, settings: settings ?? this.settings);

  Map<String, dynamic> toMap() =>
      {'id': id, 'type': type, 'settings': settings};
}

class StoreSection {
  const StoreSection({
    required this.id,
    required this.type,
    this.enabled = true,
    this.settings = const {},
    this.blocks = const [],
  });

  /// A new section of [type] with its defaults, plus [settings], and the
  /// minimum number of blocks it needs.
  factory StoreSection.create(SectionType type,
      {String? id, Map<String, Object?> settings = const {}}) {
    final sectionId = id ?? newDesignId(type.id);
    final schema = type.blocks;
    return StoreSection(
      id: sectionId,
      type: type,
      settings: _readAll(type.settings, settings),
      blocks: [
        if (schema != null)
          for (var i = 0; i < schema.min; i++) newBlock(schema),
      ],
    );
  }

  static SectionBlock newBlock(BlockSchema schema) => SectionBlock(
      id: newDesignId(schema.type),
      type: schema.type,
      settings: _readAll(schema.settings, const {}));

  final String id;
  final SectionType type;

  /// Hidden sections stay in the design but aren't rendered.
  final bool enabled;

  /// Already coerced through [SectionType.settings].
  final Map<String, Object?> settings;
  final List<SectionBlock> blocks;

  String get title {
    final t = settings['title'] ?? settings['heading'];
    return t is String && t.trim().isNotEmpty ? t : type.label;
  }

  String text(String key) => settings[key] as String? ?? '';
  bool flag(String key) => settings[key] as bool? ?? false;

  StoreSection copyWith({
    bool? enabled,
    Map<String, Object?>? settings,
    List<SectionBlock>? blocks,
  }) =>
      StoreSection(
        id: id,
        type: type,
        enabled: enabled ?? this.enabled,
        settings: settings ?? this.settings,
        blocks: blocks ?? this.blocks,
      );

  List<String> problems() {
    final out = <String>[];
    final schema = type.blocks;
    if (schema != null && blocks.length < schema.min) {
      out.add('add at least ${schema.min} ${schema.label.toLowerCase()}.');
    }
    for (final def in type.settings) {
      if (def.required &&
          def.isVisible(settings) &&
          (settings[def.key] as String? ?? '').trim().isEmpty) {
        out.add('${def.label} is required.');
      }
    }
    if (schema != null) {
      for (final block in blocks) {
        for (final def in schema.settings) {
          if (def.required &&
              (block.settings[def.key] as String? ?? '').trim().isEmpty) {
            out.add(
                'each ${schema.label.toLowerCase()} needs a ${def.label.toLowerCase()}.');
            break;
          }
        }
      }
    }
    return out.toSet().toList();
  }

  static StoreSection? tryFromMap(Map<String, dynamic> map) {
    final type = SectionType.parse(map['type']);
    final id = map['id'];
    if (type == null || id is! String || id.isEmpty) return null;
    final schema = type.blocks;
    final blocks = <SectionBlock>[];
    if (schema != null) {
      for (final raw in _list(map['blocks'])) {
        final b = _map(raw);
        final blockId = b['id'];
        if (b['type'] != schema.type || blockId is! String) continue;
        blocks.add(SectionBlock(
            id: blockId,
            type: schema.type,
            settings: _readAll(schema.settings, _map(b['settings']))));
        if (blocks.length == schema.max) break;
      }
    }
    return StoreSection(
      id: id,
      type: type,
      enabled: map['enabled'] != false,
      settings: _readAll(type.settings, _map(map['settings'])),
      blocks: blocks,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.id,
        'enabled': enabled,
        'settings': settings,
        'blocks': [for (final b in blocks) b.toMap()],
      };
}

Map<String, Object?> _readAll(
        List<SettingDef> defs, Map<String, Object?> raw) =>
    {for (final def in defs) def.key: def.read(raw[def.key])};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

var _idCounter = 0;

/// Unique within a design: a type prefix, the time, and a counter.
String newDesignId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_idCounter++).toRadixString(36)}';

/// [raw] if it's an absolute http(s) URL, else null.
String? safeUrl(Object? raw) {
  if (raw is! String) return null;
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
    return null;
  }
  if (uri.host.isEmpty) return null;
  return raw.trim();
}

String? _validHex(Object? raw) =>
    raw is String && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(raw)
        ? raw.toUpperCase()
        : null;

String _clip(Object? raw, int max) {
  if (raw is! String) return '';
  return raw.length > max ? raw.substring(0, max) : raw;
}

Map<String, dynamic> _map(Object? raw) =>
    raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

List<Object?> _list(Object? raw) => raw is List ? raw : const [];

List<StoreLink> _links(Object? raw, int max) => [
      for (final l in _list(raw))
        if (StoreLink.tryFromMap(_map(l)) case final link?) link,
    ].take(max).toList();
