import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sellora/data/models/store_design.dart';
import 'package:sellora/data/models/store_model.dart';
import 'package:sellora/data/repositories/product_repository.dart';
import 'package:sellora/data/repositories/store_design_repository.dart';
import 'package:sellora/data/repositories/store_repository.dart';
import 'package:sellora/modules/seller/store_builder/store_builder_controller.dart';
import 'package:sellora/modules/storefront/store_scope.dart';

StoreModel _store({String? banner, String? accent}) => StoreModel(
      id: 'store-1',
      slug: 'amina',
      sellerId: 'seller-1',
      name: 'Amina\'s Store',
      tagline: 'Handmade in Nairobi',
      bannerUrl: banner,
      primaryColorHex: accent,
    );

String _json(StoreDesign d) => jsonEncode(d.toMap());

void main() {
  group('StoreDesign', () {
    test('the starter design is today\'s storefront as sections', () {
      final d = StoreDesign.starter(
          _store(banner: 'https://cdn.example.com/b.jpg', accent: '#112233'));
      expect(d.sections.map((s) => s.type),
          [SectionType.hero, SectionType.catalog]);
      expect(d.sections.first.text('heading'), 'Amina\'s Store');
      expect(d.sections.first.settings['imageUrl'],
          'https://cdn.example.com/b.jpg');
      expect(d.theme.accentHex, '#112233');
      expect(d.problems(), isEmpty);
      // A legacy inline data: banner isn't carried into a design.
      expect(
          StoreDesign.starter(_store(banner: 'data:image/png;base64,AAAA'))
              .sections
              .first
              .settings['imageUrl'],
          isNull);
    });

    test('round-trips through JSON', () {
      final d = StoreDesign.starter(_store()).copyWith(
        announcement: AnnouncementBar(
            enabled: true,
            text: 'Free delivery',
            link: LinkTarget.category('Fashion')),
        footer: const FooterSettings(
            social: {SocialNetwork.instagram: 'https://instagram.com/amina'}),
        sections: [
          ...StoreDesign.starter(_store()).sections,
          StoreSection.create(SectionType.testimonials),
        ],
      );
      final copy =
          StoreDesign.fromMap(jsonDecode(_json(d)) as Map<String, dynamic>);
      expect(_json(copy), _json(d));
      expect(copy.announcement.link, LinkTarget.category('Fashion'));
      expect(copy.sections.last.blocks, hasLength(1));
    });

    test('reads a hostile or broken document defensively', () {
      final d = StoreDesign.fromMap({
        'theme': {
          'colors': {'accent': 'red; }', 'background': '#ffffff'},
          'typography': {'heading': 'Comic Sans', 'body': 'Poppins'},
          'faviconUrl': 'javascript:alert(1)',
        },
        'announcement': {
          'enabled': true,
          'text': 'x' * 500,
          'link': 'url:javascript:alert(1)',
        },
        'navigation': [
          {'label': 'Evil', 'target': 'url:javascript:alert(1)'},
          {'label': 'Shop', 'target': 'catalog'},
        ],
        'sections': [
          {'id': 'a', 'type': 'catalog'},
          {'id': 'b', 'type': 'catalog'},
          {'id': 'a', 'type': 'hero'},
          {'id': 'c', 'type': 'marquee'},
          {
            'id': 'd',
            'type': 'hero',
            'settings': {
              'imageUrl': 'data:text/html,<script>',
              'heading': 'h' * 200,
              'height': 'enormous',
              'buttonLink': 'url:http://ok.example.com/x',
            }
          },
          {
            'id': 'e',
            'type': 'imageBanner',
            'blocks': [
              for (var i = 0; i < 5; i++) {'id': 'b$i', 'type': 'banner'},
              {'id': 'x', 'type': 'testimonial'},
            ]
          },
        ],
        'footer': {
          'social': {'instagram': 'ftp://x', 'tiktok': 'https://tiktok.com/@a'},
        },
      });
      expect(d.theme.accentHex, ThemeSettings.defaultAccent);
      expect(d.theme.backgroundHex, '#FFFFFF');
      expect(d.theme.headingFont, 'Fraunces');
      expect(d.theme.bodyFont, 'Poppins');
      expect(d.theme.faviconUrl, isNull);
      expect(d.announcement.text, hasLength(AnnouncementBar.maxText));
      expect(d.announcement.link, isNull);
      expect(d.navigation.map((l) => l.label), ['Shop']);
      // One catalog, no duplicate id, no unknown type.
      expect(d.sections.map((s) => s.id), ['a', 'd', 'e']);
      final hero = d.sections[1];
      expect(hero.settings['imageUrl'], isNull);
      expect(hero.text('heading'), hasLength(80));
      expect(hero.text('height'), 'medium');
      expect(hero.settings['buttonLink'], 'url:http://ok.example.com/x');
      expect(d.sections[2].blocks, hasLength(3));
      expect(d.footer.social.keys, [SocialNetwork.tiktok]);
    });

    test('links only leave the app for http(s)', () {
      for (final bad in [
        'javascript:alert(1)',
        'data:text/html,x',
        '/relative',
        'https://',
        'mailto:a@b.co',
      ]) {
        expect(LinkTarget.url(bad), isNull, reason: bad);
      }
      expect(LinkTarget.url('https://amina.example.com')?.serialize(),
          'url:https://amina.example.com');
      expect(
          LinkTarget.parse('category:Home & living')?.value, 'Home & living');
      expect(LinkTarget.parse('category:   '), isNull);
      expect(LinkTarget.parse('catalog'), LinkTarget.catalog);
      expect(LinkTarget.parse('nowhere'), isNull);
    });

    test('says what blocks publishing', () {
      final base = StoreDesign.starter(_store());
      expect(base.copyWith(sections: []).problems(), isNotEmpty);
      final hiddenCatalog = base.copyWith(sections: [
        for (final s in base.sections)
          s.type == SectionType.catalog ? s.copyWith(enabled: false) : s,
      ]);
      expect(hiddenCatalog.problems().single, contains('All products'));
      final emptyQuote = base.copyWith(sections: [
        ...base.sections,
        StoreSection.create(SectionType.testimonials)
      ]);
      expect(emptyQuote.problems().single, contains('quote'));
      expect(
          base
              .copyWith(announcement: const AnnouncementBar(enabled: true))
              .problems()
              .single,
          contains('Announcement'));
    });

    test('a new section has its defaults and minimum blocks', () {
      final banners = StoreSection.create(SectionType.imageBanner);
      expect(banners.blocks, hasLength(1));
      expect(banners.blocks.first.settings['heading'], 'New arrivals');
      final featured = StoreSection.create(SectionType.featuredProducts);
      expect(featured.settings['source'], 'newest');
      expect(featured.settings['productIds'], isEmpty);
      expect(
          SectionType.featuredProducts.settings
              .firstWhere((d) => d.key == 'productIds')
              .isVisible(featured.settings),
          isFalse);
    });
  });

  group('StoreBuilderController', () {
    late _FakeDesigns repo;
    late StoreBuilderController controller;

    setUp(() async {
      Get.testMode = true;
      final scope = StoreScope(repository: _NoStores())
        ..current.value = _store();
      repo = _FakeDesigns();
      controller = StoreBuilderController(
          scope: scope,
          designs: repo,
          stores: _NoStores(),
          products: _NoProducts());
      await controller.load();
    });

    tearDown(Get.reset);

    StoreDesign design() => controller.design.value!;

    test('starts from the starter design, unsaved', () {
      expect(design().sections.map((s) => s.type),
          [SectionType.hero, SectionType.catalog]);
      expect(controller.isDirty, isTrue);
      expect(controller.hasUnpublishedChanges, isTrue);
    });

    test('adds sections above the catalog, one newsletter at most', () {
      controller.addSection(SectionType.richText);
      expect(design().sections.map((s) => s.type), [
        SectionType.hero,
        SectionType.richText,
        SectionType.catalog,
      ]);
      expect(controller.panel.value, isA<SectionPanel>());
      controller.addSection(SectionType.newsletter);
      expect(controller.canAdd(SectionType.newsletter), isFalse);
      controller.addSection(SectionType.newsletter);
      expect(design().sections.where((s) => s.type == SectionType.newsletter),
          hasLength(1));
    });

    test('never removes the catalog; moves, hides and duplicates', () {
      final catalog = design().sections.last;
      controller.removeSection(catalog.id);
      expect(design().sections, contains(catalog));

      controller.moveSection(1, 0);
      expect(design().sections.first.type, SectionType.catalog);
      final hero = design().sections.last;
      controller.toggleSection(hero.id);
      expect(design().sectionById(hero.id)!.enabled, isFalse);
      controller.duplicateSection(hero.id);
      expect(design().sections.where((s) => s.type == SectionType.hero),
          hasLength(2));
      controller.removeSection(hero.id);
      expect(design().sectionById(hero.id), isNull);
    });

    test('coerces settings through the schema', () {
      final hero = design().sections.first;
      controller.setSectionSetting(hero.id, 'heading', 'x' * 300);
      controller.setSectionSetting(hero.id, 'height', 'huge');
      controller.setSectionSetting(hero.id, 'imageUrl', 'javascript:x');
      final s = design().sectionById(hero.id)!;
      expect(s.text('heading'), hasLength(80));
      expect(s.text('height'), 'medium');
      expect(s.settings['imageUrl'], isNull);
    });

    test('keeps blocks within their limits', () {
      controller.addSection(SectionType.imageBanner);
      final id = design().sections[1].id;
      controller.addBlock(id);
      controller.addBlock(id);
      controller.addBlock(id);
      final s = design().sectionById(id)!;
      expect(s.blocks, hasLength(3));
      for (final b in s.blocks) {
        controller.removeBlock(id, b.id);
      }
      expect(design().sectionById(id)!.blocks, hasLength(1));
      final block = design().sectionById(id)!.blocks.single;
      controller.setBlockSetting(id, block.id, 'heading', 'Sale');
      expect(
          design().sectionById(id)!.blocks.single.settings['heading'], 'Sale');
    });

    testWidgets('saves, publishes and tracks changes', (tester) async {
      await tester.pumpWidget(const GetMaterialApp(home: SizedBox()));
      expect(await controller.saveDraft(quiet: true), isTrue);
      expect(controller.isDirty, isFalse);
      expect(repo.draft, isNotNull);

      controller
          .setAnnouncement(const AnnouncementBar(enabled: true, text: 'Sale'));
      expect(controller.isDirty, isTrue);
      expect(await controller.publish(), isEmpty);
      expect(repo.published, isNotNull);
      expect(controller.isDirty, isFalse);
      expect(controller.hasUnpublishedChanges, isFalse);
      expect(controller.scope.current.value!.primaryColorHex,
          design().theme.accentHex);

      controller.setAnnouncement(const AnnouncementBar(enabled: true));
      expect(await controller.publish(), isNotEmpty);
      controller.discardChanges();
      expect(design().announcement.text, 'Sale');
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });
}

class _FakeDesigns implements StoreDesignRepository {
  StoreDesign? draft;
  StoreDesign? published;
  int version = 0;

  @override
  Future<StoreDesignRecord?> loadForOwner(String storeId) async => draft == null
      ? null
      : StoreDesignRecord(
          draft: draft!, published: published, publishedVersion: version);

  @override
  Future<void> saveDraft(String storeId, StoreDesign d) async => draft = d;

  @override
  Future<int> publish(String storeId) async {
    published = draft;
    return ++version;
  }

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
