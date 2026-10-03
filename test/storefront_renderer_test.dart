import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sellora/data/models/product_model.dart';
import 'package:sellora/data/models/store_design.dart';
import 'package:sellora/data/models/store_model.dart';
import 'package:sellora/data/repositories/product_repository.dart';
import 'package:sellora/data/repositories/store_repository.dart';
import 'package:sellora/l10n/generated/app_localizations.dart';
import 'package:sellora/modules/storefront/design/storefront_renderer.dart';
import 'package:sellora/modules/storefront/store_scope.dart';
import 'package:sellora/modules/storefront/storefront_controller.dart';

/// Every section type at once, no images (no network in tests).
StoreDesign _everything() {
  StoreSection with_(SectionType t, Map<String, Object?> settings,
      [List<Map<String, Object?>> blocks = const []]) {
    final s = StoreSection.create(t, settings: settings);
    final schema = t.blocks;
    if (schema == null) return s;
    return s.copyWith(blocks: [
      for (final b in blocks)
        StoreSection.newBlock(schema).copyWith(settings: {
          ...StoreSection.newBlock(schema).settings,
          ...b,
        }),
    ]);
  }

  return StoreDesign(
    announcement: const AnnouncementBar(enabled: true, text: 'Free delivery'),
    navigation: const [
      StoreLink(label: 'Home', target: LinkTarget.home),
      StoreLink(label: 'Shop all', target: LinkTarget.catalog),
    ],
    sections: [
      with_(SectionType.hero, {'heading': 'Welcome in'}),
      with_(SectionType.featuredProducts, {'title': 'Picks'}),
      with_(SectionType.collectionList, {
        'title': 'Collections'
      }, [
        {'category': 'Fashion'},
        {'category': 'Home', 'label': 'For the home'},
      ]),
      with_(SectionType.imageBanner, {}, [
        {'heading': 'Banner one'},
        {'heading': 'Banner two'},
      ]),
      with_(SectionType.testimonials, {}, [
        {'quote': 'Lovely', 'author': 'Wanjiru'},
      ]),
      with_(SectionType.richText, {'heading': 'Our story', 'body': 'We make'}),
      with_(SectionType.newsletter, {}),
      StoreSection.create(SectionType.catalog),
    ],
    footer: const FooterSettings(
        aboutText: 'About us',
        social: {SocialNetwork.instagram: 'https://instagram.com/a'}),
  );
}

void main() {
  late StorefrontController controller;

  setUp(() {
    Get.testMode = true;
    Get.put<StoreScope>(StoreScope(repository: _NoStores())
      ..current.value = StoreModel(
          id: 'store-1', slug: 'a', sellerId: 's', name: 'Amina\'s Store'));
    Get.put<ProductRepository>(_EmptyProducts());
    controller = StorefrontController(previewMode: true);
  });

  tearDown(Get.reset);

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(GetMaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: StorefrontRenderer(controller: controller, design: _everything()),
      ),
    ));
    await controller.load();
    await tester.pumpAndSettle();
  }

  for (final (name, size) in [
    ('phone', const Size(390, 844)),
    ('desktop', const Size(1400, 900)),
  ]) {
    testWidgets('renders every section on a $name', (tester) async {
      await pump(tester, size);
      expect(tester.takeException(), isNull);
      expect(find.text('Free delivery'), findsOneWidget);
      expect(find.text('Welcome in'), findsOneWidget);
      expect(find.text('For the home'), findsOneWidget);
      expect(find.text('Products you list will show here.'), findsOneWidget);
      // The page is long; scroll down through it.
      final page = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.textContaining('Lovely'), 300,
          scrollable: page);
      await tester.scrollUntilVisible(find.text('Powered by Sellora'), 300,
          scrollable: page);
      expect(find.text('Instagram'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a collection tile filters the catalog by its category',
      (tester) async {
    await pump(tester, const Size(1400, 900));
    await tester.tap(find.text('Fashion'));
    await tester.pumpAndSettle();
    expect(controller.selectedCategory.value, 'Fashion');
  });

  testWidgets('the preview never signs anyone up', (tester) async {
    await pump(tester, const Size(1400, 900));
    await tester.scrollUntilVisible(find.text('Subscribe'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.widgetWithText(TextField, 'you@example.com'),
        'reader@example.com');
    await tester.tap(find.text('Subscribe'));
    await tester.pumpAndSettle();
    expect(find.textContaining('collected on your live storefront'),
        findsOneWidget);
  });
}

class _NoStores implements StoreRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyProducts implements ProductRepository {
  @override
  Future<List<ProductModel>> storeProducts(String storeId,
          {String? keyword,
          String? category,
          StoreProductSort sort = StoreProductSort.newest,
          double? minPrice,
          double? maxPrice,
          int offset = 0,
          int limit = storefrontPageSize}) async =>
      const [];

  @override
  Future<List<ProductModel>> featuredProducts(String storeId,
          {List<String>? ids, bool bestSelling = false, int limit = 8}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
