import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sellora/core/utils/color_utils.dart';
import 'package:sellora/data/models/product_model.dart';
import 'package:sellora/data/models/store_design.dart';
import 'package:sellora/data/models/store_model.dart';
import 'package:sellora/data/models/store_theme.dart';
import 'package:sellora/data/repositories/product_repository.dart';
import 'package:sellora/data/repositories/store_design_repository.dart';
import 'package:sellora/data/repositories/store_repository.dart';
import 'package:sellora/data/services/currency_service.dart';
import 'package:sellora/l10n/generated/app_localizations.dart';
import 'package:sellora/modules/seller/store_builder/store_builder_controller.dart';
import 'package:sellora/modules/seller/store_builder/theme_thumbnail.dart';
import 'package:sellora/modules/storefront/design/storefront_renderer.dart';
import 'package:sellora/modules/storefront/design/storefront_theme.dart';
import 'package:sellora/modules/storefront/store_scope.dart';
import 'package:sellora/modules/storefront/storefront_controller.dart';

StoreModel _store({String? category}) => StoreModel(
      id: 'store-1',
      slug: 'amina',
      sellerId: 'seller-1',
      name: 'Amina\'s Store',
      tagline: 'Handmade in Nairobi',
      bannerUrl: 'https://cdn.example.com/banner.jpg',
      category: category,
    );

double _contrast(String a, String b) {
  final x = hexToColor(a)!.computeLuminance();
  final y = hexToColor(b)!.computeLuminance();
  return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
}

void main() {
  group('StoreTheme', () {
    test('ships the five initial themes', () {
      expect(StoreTheme.all.map((t) => t.name), [
        'General Store',
        'Minimal',
        'Modern',
        'Fashion',
        'Electronics',
      ]);
      expect(StoreTheme.all.map((t) => t.id).toSet(), hasLength(5));
    });

    for (final theme in StoreTheme.all) {
      test('${theme.name}: readable, and its homepage can be published', () {
        final s = theme.settings;
        expect(_contrast(s.textHex, s.backgroundHex), greaterThan(4.5));
        expect(_contrast(s.textHex, s.surfaceHex), greaterThan(4.5));
        final onAccent =
            StorefrontTheme.onColor(StorefrontTheme.accent(s)).toARGB32();
        expect(
            _contrast(s.accentHex,
                '#${(onAccent & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}'),
            greaterThan(4.5));
        expect(StoreFont.valid(s.headingFont, ''), s.headingFont);
        expect(StoreFont.valid(s.bodyFont, ''), s.bodyFont);

        final design = theme.applyTo(StoreDesign.starter(_store()),
            store: _store(), homepage: true);
        expect(design.problems(), isEmpty);
        expect(design.sections.where((x) => x.type == SectionType.catalog),
            hasLength(1));
        expect(design.sections.map((x) => x.id).toSet(),
            hasLength(design.sections.length));
        // Survives a save and a reload unchanged.
        final json = jsonEncode(design.toMap());
        expect(
            jsonEncode(
                StoreDesign.fromMap(jsonDecode(json) as Map<String, dynamic>)
                    .toMap()),
            json);
      });
    }

    test('a design from before themes reads as General Store, unchanged', () {
      final old = StoreDesign.fromMap({
        'themeId': 'meridian',
        'theme': {
          'colors': {'accent': '#112233', 'background': '#FAFAFA'},
          'typography': {'heading': 'Lora', 'body': 'Inter'},
          'buttonShape': 'square',
        },
        'sections': [
          {'id': 'catalog', 'type': 'catalog'},
        ],
      });
      expect(StoreTheme.byId(old.themeId), StoreTheme.general);
      expect(old.themeVersion, 1);
      expect(StoreTheme.hasUpdate(old), isFalse);
      final t = old.theme;
      expect(t.accentHex, '#112233');
      expect(t.surfaceHex, '#FAFAFA');
      expect(t.corners, CornerStyle.round);
      expect(t.cardStyle, CardStyle.flat);
      expect(t.imageShape, ImageShape.square);
      expect(t.spacing, SectionSpacing.comfortable);
      expect(t.centeredHeader, isFalse);
      expect(t.uppercaseHeadings, isFalse);
      expect(StoreTheme.byId('no-such-theme'), StoreTheme.general);
    });

    test('reads style settings defensively', () {
      final t = ThemeSettings.fromMap({
        'colors': {'surface': 'url(x)'},
        'style': {
          'corners': 'blob',
          'cards': 'raised',
          'productImage': 'portrait',
          'spacing': 99,
          'header': 'center',
          'uppercaseHeadings': 'yes',
        },
      });
      expect(t.surfaceHex, t.backgroundHex);
      expect(t.corners, CornerStyle.round);
      expect(t.cardStyle, CardStyle.raised);
      expect(t.imageShape, ImageShape.portrait);
      expect(t.spacing, SectionSpacing.comfortable);
      expect(t.centeredHeader, isTrue);
      expect(t.uppercaseHeadings, isFalse);
      expect(StoreDesign.fromMap({'themeVersion': -3}).themeVersion, 1);
    });

    test('applying a theme keeps the seller\'s content', () {
      final before = StoreDesign.starter(_store()).copyWith(
        theme: const ThemeSettings(faviconUrl: 'https://cdn.example.com/f.png'),
        announcement: const AnnouncementBar(enabled: true, text: 'Hello'),
        navigation: const [
          StoreLink(label: 'Shop', target: LinkTarget.catalog)
        ],
        footer: const FooterSettings(aboutText: 'Since 2020'),
      );
      final styled =
          StoreTheme.fashion.applyTo(before, store: _store(), homepage: false);
      expect(styled.themeId, 'fashion');
      expect(styled.themeVersion, StoreTheme.fashion.version);
      expect(styled.theme.headingFont, 'Playfair Display');
      expect(styled.theme.imageShape, ImageShape.portrait);
      expect(styled.theme.faviconUrl, 'https://cdn.example.com/f.png');
      expect(styled.sections, same(before.sections));
      expect(styled.announcement.text, 'Hello');
      expect(styled.navigation.single.label, 'Shop');
      expect(styled.footer.aboutText, 'Since 2020');

      final rebuilt =
          StoreTheme.fashion.applyTo(before, store: _store(), homepage: true);
      expect(rebuilt.sections.first.type, SectionType.hero);
      expect(rebuilt.sections.first.text('heading'), 'Amina\'s Store');
      expect(rebuilt.sections.first.settings['imageUrl'],
          'https://cdn.example.com/banner.jpg');
      expect(rebuilt.announcement.text, 'Hello');
    });

    test('suggests a theme from the store category', () {
      expect(StoreTheme.suggestedFor('fashion'), StoreTheme.fashion);
      expect(StoreTheme.suggestedFor('electronics'), StoreTheme.electronics);
      expect(StoreTheme.suggestedFor('general'), StoreTheme.general);
      expect(StoreTheme.suggestedFor(null), StoreTheme.general);
    });

    test('offers an update when the theme is newer than the design', () {
      final d = StoreDesign.starter(_store())
          .copyWith(themeId: 'modern', themeVersion: 0);
      expect(StoreTheme.hasUpdate(d), isTrue);
      expect(
          StoreTheme.hasUpdate(StoreTheme.modern.applyTo(d, store: _store())),
          isFalse);
    });

    test('a product tile fits each photo shape', () {
      for (final shape in ImageShape.values) {
        final card =
            StoreStyle.from(ThemeSettings(imageShape: shape)).productCard;
        expect(card.imageAspectRatio, shape.aspectRatio);
      }
      expect(const ThemeSettings().imageShape.aspectRatio, 1);
      expect(StoreStyle.from(const ThemeSettings()).productCard.tileAspectRatio,
          closeTo(0.62, 0.01));
    });
  });

  group('StoreBuilderController themes', () {
    late StoreBuilderController controller;

    setUp(() async {
      Get.testMode = true;
      controller = StoreBuilderController(
          scope: StoreScope(repository: _NoStores())
            ..current.value = _store(category: 'fashion'),
          designs: _NoDesigns(),
          stores: _NoStores(),
          products: _NoProducts());
      await controller.load();
    });

    tearDown(Get.reset);

    test('applies a theme, and undoes it until the next edit', () {
      final original = controller.design.value!;
      expect(controller.currentTheme, StoreTheme.general);
      expect(controller.suggestedTheme, StoreTheme.fashion);

      controller.applyTheme(StoreTheme.minimal, homepage: true);
      expect(controller.currentTheme, StoreTheme.minimal);
      expect(
          controller.design.value!.sections.first.type, SectionType.richText);
      controller.undoTheme();
      expect(controller.design.value, same(original));

      controller.applyTheme(StoreTheme.modern);
      expect(controller.design.value!.sections, same(original.sections));
      controller.setTheme(controller.design.value!.theme
          .copyWith(cardStyle: CardStyle.outlined));
      expect(controller.beforeTheme.value, isNull);
      controller.undoTheme();
      expect(controller.currentTheme, StoreTheme.modern);
      expect(controller.design.value!.theme.cardStyle, CardStyle.outlined);
    });

    test('back from the gallery returns to the theme panel', () {
      controller.open(const ThemeLibraryPanel());
      controller.back();
      expect(controller.panel.value, isA<ThemePanel>());
    });
  });

  group('rendering each theme', () {
    late StorefrontController storefront;

    setUp(() {
      Get.testMode = true;
      Get.put<CurrencyService>(_Currency());
      Get.put<StoreScope>(
          StoreScope(repository: _NoStores())..current.value = _store());
      Get.put<ProductRepository>(_SomeProducts());
      storefront = StorefrontController(previewMode: true);
    });

    tearDown(Get.reset);

    for (final theme in StoreTheme.all) {
      for (final (device, size) in [
        ('phone', const Size(390, 844)),
        ('desktop', const Size(1400, 900)),
      ]) {
        testWidgets('${theme.name} on a $device', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final design = theme.applyTo(StoreDesign.starter(_store()),
              store: _store(), homepage: true);
          await tester.pumpWidget(GetMaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            // The theme's style without its Google Fonts, which tests
            // can't fetch.
            theme: ThemeData(extensions: [StoreStyle.from(design.theme)]),
            home: Scaffold(
              body: Column(
                children: [
                  SizedBox(
                      height: 150,
                      width: 240,
                      child: ThemeThumbnail(settings: design.theme)),
                  Expanded(
                    child: StorefrontRenderer(
                        controller: storefront, design: design),
                  ),
                ],
              ),
            ),
          ));
          await storefront.load();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          // Down through the featured row and the catalog grid.
          await tester.scrollUntilVisible(find.text('Powered by Sellora'), 300,
              scrollable: find.byType(Scrollable).first);
          expect(find.textContaining('Gadget'), findsWidgets);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}

class _Currency extends GetxService implements CurrencyService {
  final _code = 'KES'.obs;

  @override
  String format(double amount, {String fromCode = 'USD'}) =>
      '${_code.value} ${amount.toStringAsFixed(0)}';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SomeProducts implements ProductRepository {
  static final _items = [
    for (var i = 1; i <= 6; i++)
      ProductModel(
        id: 'p$i',
        cjProductId: 'cj$i',
        title: 'Gadget $i with a fairly long product title',
        imageUrl: '',
        costPrice: 10,
        sellPrice: 1999,
        compareAtPrice: 2499,
        category: 'Electronics',
        soldCount: 12,
      ),
  ];

  @override
  Future<List<ProductModel>> storeProducts(String storeId,
          {String? keyword,
          String? category,
          int offset = 0,
          int limit = storefrontPageSize}) async =>
      offset == 0 ? _items : const [];

  @override
  Future<List<ProductModel>> featuredProducts(String storeId,
          {List<String>? ids, bool bestSelling = false, int limit = 8}) async =>
      _items.take(limit).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoDesigns implements StoreDesignRepository {
  @override
  Future<StoreDesignRecord?> loadForOwner(String storeId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoStores implements StoreRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoProducts implements ProductRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
