import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sellora/core/i18n/money.dart';
import 'package:sellora/data/models/notification_model.dart';
import 'package:sellora/data/models/order_model.dart';
import 'package:sellora/data/models/product_model.dart';
import 'package:sellora/data/models/store_design.dart';
import 'package:sellora/data/models/store_model.dart';
import 'package:sellora/data/models/store_page.dart';
import 'package:sellora/data/models/user_model.dart';
import 'package:sellora/data/repositories/auth_repository.dart';
import 'package:sellora/data/repositories/cart_repository.dart';
import 'package:sellora/data/repositories/discount_repository.dart';
import 'package:sellora/data/repositories/notification_repository.dart';
import 'package:sellora/data/repositories/order_repository.dart';
import 'package:sellora/data/repositories/product_repository.dart';
import 'package:sellora/data/repositories/store_design_repository.dart';
import 'package:sellora/data/repositories/store_page_repository.dart';
import 'package:sellora/data/repositories/store_repository.dart';
import 'package:sellora/data/services/currency_service.dart';
import 'package:sellora/data/services/order_payment_provider.dart';
import 'package:sellora/data/services/storage_service.dart';
import 'package:sellora/l10n/generated/app_localizations.dart';
import 'package:sellora/modules/auth/controllers/auth_controller.dart';
import 'package:sellora/modules/buyer/buyer_binding.dart';
import 'package:sellora/modules/buyer/cart/cart_view.dart';
import 'package:sellora/modules/buyer/checkout/checkout_controller.dart';
import 'package:sellora/modules/buyer/checkout/checkout_view.dart';
import 'package:sellora/modules/buyer/orders/order_page.dart';
import 'package:sellora/modules/buyer/product_details/product_details_controller.dart';
import 'package:sellora/modules/buyer/product_details/product_details_view.dart';
import 'package:sellora/modules/buyer/profile/buyer_profile_view.dart';
import 'package:sellora/modules/notifications/notification_center.dart';
import 'package:sellora/modules/seller/store_pages/store_pages_controller.dart';
import 'package:sellora/modules/storefront/pages/product_list_page.dart';
import 'package:sellora/modules/storefront/pages/store_page_view.dart';
import 'package:sellora/modules/storefront/store_scope.dart';
import 'package:sellora/modules/storefront/storefront_login_view.dart';
import 'package:sellora/modules/storefront/storefront_register_view.dart';
import 'package:sellora/modules/storefront/storefront_session.dart';

final _store = StoreModel(
    id: 'store-1', slug: 'amina', sellerId: 'seller-1', name: 'Amina\'s Store');

ProductModel _product(String id, {String category = 'Home & Living'}) =>
    ProductModel(
      id: id,
      cjProductId: 'cj-$id',
      title: 'Lamp $id',
      imageUrl: '',
      costPrice: 10,
      sellPrice: 2500,
      currency: 'KES',
      category: category,
      storeId: _store.id,
    );

UserModel _buyer({String storeId = 'store-1'}) => UserModel(
    uid: 'buyer-1',
    name: 'Wanjiru',
    email: 'w@example.com',
    role: UserRole.buyer,
    storeId: storeId);

OrderModel _order({String id = 'o1', String storeId = 'store-1'}) => OrderModel(
      id: id,
      code: 'SLR-1001',
      buyerId: 'buyer-1',
      sellerId: 'seller-1',
      storeId: storeId,
      items: [
        OrderItem(
            productId: 'p1',
            title: 'Lamp p1',
            imageUrl: '',
            quantity: 2,
            unitPrice: 2500,
            variantLabel: 'Brass'),
      ],
      status: OrderStatus.pending,
      total: 5500,
      currency: 'KES',
      shippingAddress: ShippingAddress(
          countryCode: 'KE',
          fullName: 'Wanjiru',
          phone: '0711000000',
          line1: '1 Moi Ave',
          city: 'Nairobi'),
      paymentMethod: 'M-Pesa',
      createdAt: DateTime(2026, 10, 4),
      shippingFee: 500,
    );

late _Stores _stores;
late _Designs _designs;
late _Pages _pages;
late _Products _products;
late _Auth _auth;
late _Orders _orders;

/// Everything a storefront page reaches through Get.
void _registerAll() {
  Get.testMode = true;
  _stores = _Stores();
  _designs = _Designs();
  _pages = _Pages();
  _products = _Products();
  _auth = _Auth();
  _orders = _Orders();
  Get.put<CurrencyService>(_Currency());
  Get.put<StoreRepository>(_stores);
  Get.put<StoreDesignRepository>(_designs);
  Get.put<StorePageRepository>(_pages);
  Get.put<ProductRepository>(_products);
  Get.put<AuthRepository>(_auth);
  Get.put<OrderRepository>(_orders);
  Get.put<NotificationRepository>(_NoNotifications());
  Get.put(CartRepository());
  Get.put(StoreScope());
  Get.put(NotificationCenter());
  Get.put(StorefrontSession());
}

void main() {
  group('StorePage', () {
    test('says what stops it being saved', () {
      const page = StorePage(kind: StorePageKind.refund, title: ' ');
      expect(page.problems(), contains('Give the page a title.'));
      expect(page.problems(), contains('Write something for this page.'));
      expect(
          const StorePage(kind: StorePageKind.contact, title: 'Contact')
              .problems()
              .single,
          contains('Add an email'));
      expect(
          const StorePage(
                  kind: StorePageKind.contact,
                  title: 'Contact',
                  email: 'nope',
                  phone: '12')
              .problems(),
          hasLength(2));
    });

    test('an unfinished template can be saved hidden, not published', () {
      final template = StorePageTemplates.of(StorePageKind.refund, 'Amina');
      expect(StorePageTemplates.hasBlanks(template.body), isTrue);
      expect(template.problems().single, contains('[bracketed]'));
      expect(template.copyWith(isPublished: false).problems(), isEmpty);
      final filled = template.copyWith(
          body: template.body.replaceAll(RegExp(r'\[[^\]]+\]'), '14'));
      expect(filled.problems(), isEmpty);
    });

    test('every kind has a template naming the store where it should', () {
      for (final kind in StorePageKind.values) {
        final t = StorePageTemplates.of(kind, 'Amina\'s Store');
        expect(t.title, kind.defaultTitle);
        expect(t.body, isNotEmpty);
      }
      expect(StorePageTemplates.of(StorePageKind.privacy, 'Amina').body,
          contains('Amina collects'));
    });

    test('reads rows defensively and writes only its columns', () {
      expect(StorePage.tryFromMap({'kind': 'cookies', 'title': 'x'}), isNull);
      final page = StorePage.tryFromMap({
        'kind': 'contact',
        'title': 'Say hi',
        'body': 'One.\n\n  \n\nTwo.',
        'email': ' ',
        'phone': '+254 711 000 000',
        'isPublished': false,
      })!;
      expect(page.email, isNull);
      expect(page.isPublished, isFalse);
      expect(page.paragraphs, ['One.', 'Two.']);
      expect(page.whatsappUri.toString(), 'https://wa.me/254711000000');
      final about =
          const StorePage(kind: StorePageKind.about, title: 'About', body: 'Hi')
              .copyWith(email: 'a@b.co');
      expect(about.toMap()['email'], isNull);
      expect(StorePageKind.fromPath('refund-policy'), StorePageKind.refund);
    });
  });

  group('links', () {
    test('store pages, collections and search are link targets', () {
      for (final raw in ['collections', 'search', 'page:refund']) {
        expect(LinkTarget.parse(raw)?.serialize(), raw);
      }
      expect(LinkTarget.parse('page:cookies'), isNull);
      expect(LinkTarget.page(StorePageKind.about).describe, 'About us');
    });

    test('collection handles', () {
      expect(
          StorefrontSession.collectionHandle('Home & Living'), 'home-living');
      expect(StorefrontSession.collectionHandle(' Kids/Baby! '), 'kids-baby');
    });

    test('sign-in only returns to a page of the same store', () {
      String r(String? to) => AuthController.storeReturnPath('amina', to);
      expect(r(null), '/s/amina');
      expect(r('/s/amina/checkout'), '/s/amina/checkout');
      expect(r('/s/amina/orders/o1'), '/s/amina/orders/o1');
      expect(r('/s/other/checkout'), '/s/amina');
      expect(r('https://evil.example.com/s/amina/x'), '/s/amina');
      expect(r('/s/amina/../../admin'), '/s/amina');
      expect(r('/s/amina/login?return=/s/amina/login'), '/s/amina');
      expect(r('/s/aminax/checkout'), '/s/amina');
    });
  });

  group('CartRepository', () {
    test('two options of one product are separate lines', () {
      final cart = CartRepository();
      final p = ProductModel(
        id: 'p1',
        cjProductId: 'cj',
        title: 'Shirt',
        imageUrl: '',
        costPrice: 1,
        sellPrice: 10,
        category: 'Fashion',
        variants: [
          ProductVariant(vid: 's', attributes: {'Size': 'Small'}),
          ProductVariant(vid: 'l', attributes: {'Size': 'Large'}),
        ],
      );
      cart.add(p, variant: p.variants[0]);
      cart.add(p, variant: p.variants[1], quantity: 2);
      expect(cart.items, hasLength(2));
      cart.updateQuantity(cart.items[1], 5);
      expect(cart.items.map((i) => i.quantity), [1, 5]);
      cart.remove(cart.items[0]);
      expect(cart.items.single.selectedVariant!.vid, 'l');
      cart.updateQuantity(cart.items.single, 0);
      expect(cart.items, isEmpty);
    });
  });

  group('StorefrontSession', () {
    setUp(_registerAll);
    tearDown(Get.reset);

    test('loads the store, its design, pages and categories once', () async {
      final session = Get.find<StorefrontSession>();
      await Future.wait([session.ensure('Amina'), session.ensure('amina')]);
      expect(_stores.lookups, 1);
      expect(session.isReadyFor('amina'), isTrue);
      expect(session.design.value!.sections.map((s) => s.type),
          [SectionType.hero, SectionType.catalog]);
      expect(session.pages.keys, [StorePageKind.refund]);
      expect(session.categories, ['Home & Living']);
      expect(Get.find<CartRepository>().storeId, 'store-1');
      expect(session.categoryForHandle('home-living'), 'Home & Living');
      expect(session.path('cart'), '/s/amina/cart');
    });

    test('a missing store can be retried', () async {
      final session = Get.find<StorefrontSession>();
      await session.ensure('nope');
      expect(session.isReadyFor('nope'), isFalse);
      expect(session.scope.errorMessage.value, isNotNull);
      await session.ensure('nope');
      expect(_stores.lookups, 2);
    });

    test('knows whether the visitor is this store\'s customer', () async {
      final session = Get.find<StorefrontSession>();
      await session.ensure('amina');
      expect(session.customer, isNull);
      _auth.user = _buyer(storeId: 'store-2');
      expect(session.customer, isNull);
      _auth.user = _buyer();
      expect(session.customer?.uid, 'buyer-1');
    });
  });

  group('page controllers', () {
    setUp(_registerAll);
    tearDown(Get.reset);

    test('a product page loads by id when opened from a link', () async {
      final c = ProductDetailsController(slug: 'amina', productId: 'p2');
      await c.load();
      expect(c.product.value?.id, 'p2');
      expect(_products.fetchedIds, ['p2']);

      final missing = ProductDetailsController(slug: 'amina', productId: 'x');
      await missing.load();
      expect(missing.notFound.value, isTrue);

      final fromCard = ProductDetailsController(
          slug: 'amina', productId: 'p1', initial: _product('p1'));
      await fromCard.load();
      expect(fromCard.product.value?.id, 'p1');
      expect(_products.fetchedIds, ['p2', 'x']);
    });

    test('a collection is found by its handle', () async {
      final c = ProductListController(
          mode: ProductListMode.collection,
          slug: 'amina',
          handle: 'home-living');
      c.onInit();
      await pumpEventQueue();
      expect(c.category.value, 'Home & Living');
      expect(c.items, hasLength(2));
      expect(_products.lastCategory, 'Home & Living');

      final gone = ProductListController(
          mode: ProductListMode.collection, slug: 'amina', handle: 'garden');
      gone.onInit();
      await pumpEventQueue();
      expect(gone.notFound.value, isTrue);
    });

    test('search waits for a query', () async {
      final c =
          ProductListController(mode: ProductListMode.search, slug: 'amina');
      c.onInit();
      await pumpEventQueue();
      expect(c.items, isEmpty);
      expect(_products.listCalls, 0);
      c.query.value = 'lamp';
      await c.load();
      expect(_products.lastKeyword, 'lamp');
      expect(c.items, isNotEmpty);
    });

    test('an order page is only for the customer who placed it', () async {
      final guest = OrderPageController(slug: 'amina', orderId: 'o1');
      await guest.load();
      expect(guest.order.value, isNull);
      expect(_orders.lookups, 0);

      _auth.user = _buyer();
      final mine = OrderPageController(slug: 'amina', orderId: 'o1');
      await mine.load();
      expect(mine.order.value?.code, 'SLR-1001');

      final otherStore = OrderPageController(slug: 'amina', orderId: 'o2');
      await otherStore.load();
      expect(otherStore.notFound.value, isTrue);

      final placed = OrderPageController(
          slug: 'amina',
          orderId: 'o1',
          arguments: {'placed': _order(), 'message': 'Check your phone'});
      expect(placed.justPlaced, isTrue);
      expect(placed.order.value, isNotNull);
    });
  });

  group('StorePagesController', () {
    late _Pages repo;
    late StorePagesController c;

    setUp(() async {
      Get.testMode = true;
      repo = _Pages();
      c = StorePagesController(
          scope: StoreScope(repository: _Stores())..current.value = _store,
          repository: repo);
      await c.load();
    });

    tearDown(Get.reset);

    testWidgets('writes from a template, published only once filled in',
        (tester) async {
      await tester.pumpWidget(const GetMaterialApp(home: SizedBox()));
      c.edit(StorePageKind.shipping);
      expect(c.isDirty, isFalse);
      c.useTemplate();
      expect(c.isDirty, isTrue);
      expect(await c.save(), isNotEmpty);
      expect(repo.saved, isEmpty);

      c.change(c.editing.value!.copyWith(isPublished: false));
      expect(await c.save(), isEmpty);
      expect(repo.saved.single.isPublished, isFalse);
      expect(c.pages[StorePageKind.shipping], isNotNull);

      await c.delete(StorePageKind.shipping);
      expect(c.pages[StorePageKind.shipping], isNull);
      expect(c.editing.value, isNull);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });

  group('storefront pages', () {
    setUp(_registerAll);
    tearDown(Get.reset);

    Future<void> open(WidgetTester tester, String route,
        {Size size = const Size(390, 844)}) async {
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
        initialRoute: route,
        getPages: [
          GetPage(name: '/s/:slug', page: () => const Scaffold()),
          GetPage(
              name: '/s/:slug/pages/:page', page: () => const StorePageView()),
          GetPage(
              name: '/s/:slug/products/:productId',
              page: () => const ProductDetailsView(),
              binding: ProductDetailsBinding()),
          GetPage(
              name: '/s/:slug/cart',
              page: () => const CartView(),
              binding: CartBinding()),
          GetPage(
              name: '/s/:slug/collections',
              page: () => const CollectionsPage()),
          GetPage(
              name: '/s/:slug/shop',
              page: () => const ProductListPage(mode: ProductListMode.shop)),
          GetPage(
              name: '/s/:slug/search',
              page: () => const ProductListPage(mode: ProductListMode.search)),
          GetPage(
              name: '/s/:slug/orders/:orderId',
              page: () => const OrderPage(),
              binding: OrderPageBinding()),
          GetPage(
              name: '/s/:slug/account', page: () => const BuyerProfileView()),
        ],
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('a policy page opened straight from its link', (tester) async {
      await open(tester, '/s/amina/pages/refund-policy');
      expect(tester.takeException(), isNull);
      expect(find.text('Amina\'s Store'), findsWidgets);
      expect(find.text('Returns within 14 days.'), findsOneWidget);
      // Footer link to the same page.
      expect(find.widgetWithText(TextButton, 'Refund policy'), findsOneWidget);
    });

    testWidgets('an unpublished page says so', (tester) async {
      await open(tester, '/s/amina/pages/privacy-policy');
      expect(find.text('This page isn\'t available'), findsOneWidget);
    });

    testWidgets('a product link works without the product card',
        (tester) async {
      await open(tester, '/s/amina/products/p2', size: const Size(1280, 900));
      expect(tester.takeException(), isNull);
      expect(find.text('Lamp p2'), findsOneWidget);
      await tester.tap(find.text('Buy now'));
      await tester.pumpAndSettle();
      expect(Get.find<CartRepository>().items.single.product.id, 'p2');
      // Buy now goes to the cart.
      expect(find.text('Subtotal'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the collections page lists the store\'s categories',
        (tester) async {
      await open(tester, '/s/amina/collections');
      expect(find.text('Home & Living'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final (device, size) in [
      ('phone', const Size(390, 844)),
      ('desktop', const Size(1400, 900)),
    ]) {
      testWidgets('the shop lists products with category chips on a $device',
          (tester) async {
        await open(tester, '/s/amina/shop', size: size);
        expect(tester.takeException(), isNull);
        expect(find.text('Lamp p1'), findsOneWidget);
        expect(
            find.widgetWithText(ChoiceChip, 'Home & Living'), findsOneWidget);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Home & Living'));
        await tester.pumpAndSettle();
        expect(_products.lastCategory, 'Home & Living');
      });
    }

    testWidgets('search reads its query from the link', (tester) async {
      await open(tester, '/s/amina/search?q=lamp');
      expect(_products.lastKeyword, 'lamp');
      expect(find.text('Lamp p2'), findsOneWidget);
    });

    testWidgets('the order confirmation, for its customer', (tester) async {
      _auth.user = _buyer();
      await open(tester, '/s/amina/orders/o1', size: const Size(1280, 900));
      expect(tester.takeException(), isNull);
      expect(find.text('Order SLR-1001'), findsOneWidget);
      expect(find.text('2 × Lamp p1'), findsOneWidget);
      expect(find.text('Brass'), findsOneWidget);
      expect(find.text('KES 5500'), findsOneWidget);
    });

    testWidgets('a guest asked to sign in for an order', (tester) async {
      await open(tester, '/s/amina/orders/o1');
      expect(find.text('Sign in to see this order'), findsOneWidget);
      expect(_orders.lookups, 0);
    });

    testWidgets('the account page offers a guest sign-in', (tester) async {
      await open(tester, '/s/amina/account');
      expect(find.text("You're browsing as a guest"), findsOneWidget);
    });

    testWidgets('an unknown store says so', (tester) async {
      await open(tester, '/s/nope/cart');
      expect(find.text('This storefront could not be found.'), findsOneWidget);
    });
  });

  group('customer experience (TODO §21)', () {
    setUp(_registerAll);
    tearDown(Get.reset);

    test('sort and price range read from a link', () {
      expect(
          StoreProductSort.parse('price-asc'), StoreProductSort.priceLowHigh);
      expect(StoreProductSort.parse(null), StoreProductSort.newest);
      expect(StoreProductSort.parse('cheapest'), StoreProductSort.newest);
      for (final s in StoreProductSort.values) {
        expect(StoreProductSort.parse(s.param), s);
      }

      final both = PriceRange.fromParameters(
          {'min': '100', 'max': '2500', 'cur': 'kes'});
      expect((both?.min, both?.max, both?.currency), (100, 2500, 'KES'));
      final from = PriceRange.fromParameters({'min': '10', 'cur': 'USD'});
      expect((from?.min, from?.max), (10, null));
      expect(PriceRange.fromParameters({'min': '-5', 'cur': 'KES'}), isNull);
      expect(PriceRange.fromParameters({'min': 'abc', 'cur': 'KES'}), isNull);
      expect(PriceRange.fromParameters({'min': '10', 'cur': 'XYZ'}), isNull);
      expect(PriceRange.fromParameters({'min': '10'}), isNull);
      expect(both!.toParameters(), {'min': '100', 'max': '2500', 'cur': 'KES'});
    });

    test('the shop starts from its link and keeps the link up to date',
        () async {
      final paths = <String>[];
      final c = ProductListController(
        mode: ProductListMode.shop,
        slug: 'amina',
        parameters: {
          'sort': 'price-desc',
          'min': '1000',
          'max': '3000',
          'cur': 'KES',
          'category': 'home & living',
        },
        onPathChanged: paths.add,
      );
      c.onInit();
      await pumpEventQueue();
      expect(_products.lastSort, StoreProductSort.priceHighLow);
      expect((_products.lastMinPrice, _products.lastMaxPrice), (1000, 3000));
      expect(_products.lastCategory, 'Home & Living');
      expect(c.activeFilterCount, 2);
      expect(paths, isEmpty, reason: 'opening a link doesn\'t rewrite it');

      c.setSort(StoreProductSort.bestSelling);
      await pumpEventQueue();
      expect(_products.lastSort, StoreProductSort.bestSelling);
      expect(Uri.parse(paths.last).queryParameters, {
        'category': 'Home & Living',
        'sort': 'best-selling',
        'min': '1000',
        'max': '3000',
        'cur': 'KES',
      });

      c.clearFilters();
      await pumpEventQueue();
      expect((_products.lastMinPrice, _products.lastMaxPrice), (null, null));
      expect(_products.lastCategory, 'All');
      expect(paths.last, '/s/amina/shop?sort=best-selling');

      c.setSort(StoreProductSort.newest);
      expect(paths.last, '/s/amina/shop');
    });

    test('a category the store doesn\'t have is ignored', () async {
      final c = ProductListController(
          mode: ProductListMode.shop,
          slug: 'amina',
          parameters: {'category': 'Garden'},
          onPathChanged: (_) {});
      c.onInit();
      await pumpEventQueue();
      expect(c.category.value, 'All');
    });

    test('a price range in another currency is converted', () async {
      final c = ProductListController(
          mode: ProductListMode.shop, slug: 'amina', onPathChanged: (_) {});
      c.onInit();
      await pumpEventQueue();
      // Typed in dollars; the listings are in shillings (KES 130 = $1).
      Get.find<CurrencyService>().code.value = 'USD';
      c.setPriceRange(30, 10.5); // the wrong way round
      await pumpEventQueue();
      expect(c.priceRange.value?.min, 10.5);
      expect(c.priceRange.value?.currency, 'USD');
      expect(_products.lastMinPrice, 1365);
      expect(_products.lastMaxPrice, 3900);
      c.setPriceRange(null, null);
      expect(c.priceRange.value, isNull);
    });

    test('search keeps its query in the link', () async {
      final paths = <String>[];
      final c = ProductListController(
          mode: ProductListMode.search,
          slug: 'amina',
          query: 'lamp',
          onPathChanged: paths.add);
      c.onInit();
      await pumpEventQueue();
      c.setSort(StoreProductSort.priceLowHigh);
      expect(paths.last, '/s/amina/search?q=lamp&sort=price-asc');
    });

    test('a collection\'s link keeps its handle', () async {
      final paths = <String>[];
      final c = ProductListController(
          mode: ProductListMode.collection,
          slug: 'amina',
          handle: 'home-living',
          onPathChanged: paths.add);
      c.onInit();
      await pumpEventQueue();
      expect(c.canPickCategory, isFalse);
      c.setSort(StoreProductSort.titleAz);
      expect(paths.last, '/s/amina/collections/home-living?sort=title-asc');
      expect(c.activeFilterCount, 0);
    });

    test('checkout offers the address of the last order here', () async {
      _registerCheckout();
      _auth.user = _buyer();
      Get.find<CartRepository>().setStore('store-1');
      _orders.history = [_order(id: 'o3'), _order(id: 'o1')];
      final c = CheckoutController();
      await c.loadSavedAddress();
      expect(c.savedAddress.value?.line1, '1 Moi Ave');

      _orders.history = const [];
      final none = CheckoutController();
      await none.loadSavedAddress();
      expect(none.savedAddress.value, isNull);
    });

    Future<void> open(WidgetTester tester, String route,
        {Size size = const Size(390, 844)}) async {
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
        initialRoute: route,
        getPages: [
          GetPage(name: '/s/:slug', page: () => const Scaffold()),
          GetPage(
              name: '/s/:slug/shop',
              page: () => const ProductListPage(mode: ProductListMode.shop)),
          GetPage(
              name: '/s/:slug/login', page: () => const StorefrontLoginView()),
          GetPage(
              name: '/s/:slug/register',
              page: () => const StorefrontRegisterView()),
          GetPage(
              name: '/s/:slug/checkout',
              page: () => const CheckoutView(),
              binding: CheckoutBinding()),
        ],
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the shop sorts and filters by price', (tester) async {
      await open(tester, '/s/amina/shop?sort=price-asc');
      expect(tester.takeException(), isNull);
      expect(_products.lastSort, StoreProductSort.priceLowHigh);
      expect(find.text('Price: low to high'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('product-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Best selling').last);
      await tester.pumpAndSettle();
      expect(_products.lastSort, StoreProductSort.bestSelling);

      await tester.tap(find.byKey(const ValueKey('product-price-filter')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('price-min')), '1,000');
      await tester.enterText(find.byKey(const ValueKey('price-max')), '3000');
      await tester.tap(find.byKey(const ValueKey('price-apply')));
      await tester.pumpAndSettle();
      expect((_products.lastMinPrice, _products.lastMaxPrice), (1000, 3000));
      // The range shows as a chip that removes it.
      expect(find.byType(InputChip), findsOneWidget);
      await tester.tap(find.byTooltip('Remove price filter'));
      await tester.pumpAndSettle();
      expect(_products.lastMinPrice, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sign-in is in the store\'s frame', (tester) async {
      _registerAuth();
      await open(tester, '/s/amina/login');
      expect(tester.takeException(), isNull);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Amina\'s Store'), findsOneWidget); // the top bar
      expect(find.text('Sign in to keep shopping at Amina\'s Store.'),
          findsOneWidget);
      // Show/hide password.
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(find.byTooltip('Hide password'), findsOneWidget);

      await tester.tap(find.text('New here? Create an account'));
      await tester.pumpAndSettle();
      expect(find.text('Join Amina\'s Store'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sign-in for an unknown store says so', (tester) async {
      _registerAuth();
      await open(tester, '/s/nope/login');
      expect(find.text('This storefront could not be found.'), findsOneWidget);
    });

    testWidgets('checkout fills in the last address', (tester) async {
      _registerCheckout();
      _auth.user = _buyer();
      _orders.history = [_order()];
      await open(tester, '/s/amina/checkout', size: const Size(800, 1400));
      expect(tester.takeException(), isNull);
      expect(
          find.text('Filled in from your last order. Check it\'s still '
              'right.'),
          findsOneWidget);
      expect(find.widgetWithText(TextFormField, '1 Moi Ave'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Nairobi'), findsOneWidget);
    });

    testWidgets('checkout leaves the address empty with no earlier order',
        (tester) async {
      _registerCheckout();
      _auth.user = _buyer();
      await open(tester, '/s/amina/checkout', size: const Size(800, 1400));
      expect(tester.takeException(), isNull);
      expect(
          find.textContaining('Filled in from your last order'), findsNothing);
      expect(
          find.widgetWithText(TextFormField, 'Street address'), findsOneWidget);
    });
  });
}

/// What the store sign-in pages add to [_registerAll].
void _registerAuth() {
  Get.put<StorageService>(_Storage());
  Get.put(AuthController());
}

/// What checkout adds to [_registerAll].
void _registerCheckout() {
  Get.put<OrderPaymentProvider>(_Payments());
  Get.put<DiscountRepository>(_Discounts());
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _Stores implements StoreRepository {
  int lookups = 0;

  @override
  Future<StoreModel?> storeBySlug(String slug) async {
    lookups++;
    await Future<void>.delayed(Duration.zero);
    return slug == 'amina' ? _store : null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Designs implements StoreDesignRepository {
  @override
  Future<StoreDesign?> publishedDesign(String storeId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Pages implements StorePageRepository {
  final saved = <StorePage>[];
  final _owner = <StorePageKind, StorePage>{};

  @override
  Future<Map<StorePageKind, StorePage>> publishedPages(String storeId) async =>
      {
        StorePageKind.refund: const StorePage(
            kind: StorePageKind.refund,
            title: 'Refund policy',
            body: 'Returns within 14 days.'),
      };

  @override
  Future<Map<StorePageKind, StorePage>> ownerPages(String storeId) async =>
      Map.of(_owner);

  @override
  Future<void> savePage(String storeId, StorePage page) async {
    saved.add(page);
    _owner[page.kind] = page;
  }

  @override
  Future<void> deletePage(String storeId, StorePageKind kind) async =>
      _owner.remove(kind);
}

class _Products implements ProductRepository {
  final fetchedIds = <String>[];
  int listCalls = 0;
  String? lastCategory;
  String? lastKeyword;
  StoreProductSort? lastSort;
  double? lastMinPrice;
  double? lastMaxPrice;
  final _all = [_product('p1'), _product('p2')];

  @override
  Future<List<String>> storeCategories(String storeId) async =>
      ['Home & Living'];

  @override
  Future<List<ProductModel>> storeProducts(String storeId,
      {String? keyword,
      String? category,
      StoreProductSort sort = StoreProductSort.newest,
      double? minPrice,
      double? maxPrice,
      int offset = 0,
      int limit = storefrontPageSize}) async {
    listCalls++;
    lastSort = sort;
    lastMinPrice = minPrice;
    lastMaxPrice = maxPrice;
    lastCategory = category;
    lastKeyword = keyword;
    return offset == 0 ? _all : const [];
  }

  @override
  Future<List<ProductModel>> featuredProducts(String storeId,
      {List<String>? ids, bool bestSelling = false, int limit = 8}) async {
    if (ids != null) fetchedIds.addAll(ids);
    return _all.where((p) => ids == null || ids.contains(p.id)).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements AuthRepository {
  UserModel? user;

  @override
  UserModel? get cachedUser => user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Orders implements OrderRepository {
  int lookups = 0;
  List<OrderModel> history = const [];

  @override
  Future<List<OrderModel>> buyerStoreOrders(
          String buyerId, String storeId) async =>
      history;

  @override
  Future<OrderModel?> buyerOrder(String orderId) async {
    lookups++;
    return switch (orderId) {
      'o1' => _order(),
      'o2' => _order(id: 'o2', storeId: 'store-2'),
      _ => null,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoNotifications implements NotificationRepository {
  @override
  Stream<List<AppNotification>> watchForUser(String userId) =>
      Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Currency extends GetxService implements CurrencyService {
  @override
  final code = 'KES'.obs;

  @override
  String format(double amount, {String fromCode = 'USD'}) =>
      '${code.value} ${amount.toStringAsFixed(0)}';

  /// KES 130 to the dollar.
  @override
  Money convertMoney(Money amount, String toCode) {
    if (amount.currency == toCode) return amount;
    final rate = toCode == 'KES' ? 130.0 : 1 / 130;
    return Money.fromMajor(amount.toMajor() * rate, toCode);
  }

  @override
  bool isConverted(String fromCode) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Storage extends GetxService implements StorageService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Payments implements OrderPaymentProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Discounts implements DiscountRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
