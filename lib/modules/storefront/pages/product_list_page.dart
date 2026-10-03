import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_metrics.dart';
import '../../../core/i18n/currencies.dart';
import '../../../core/i18n/money.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/app_page.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/product_card.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/store_design.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/services/currency_service.dart';
import '../design/storefront_theme.dart';
import '../shell/storefront_links.dart';
import '../shell/storefront_page.dart';
import '../storefront_session.dart';

enum ProductListMode { shop, collection, search }

/// A price band a visitor filters by, in the [currency] they typed it in
/// (their display currency then). Either end may be open.
class PriceRange {
  const PriceRange({this.min, this.max, required this.currency});
  final double? min;
  final double? max;
  final String currency;

  bool get isEmpty => min == null && max == null;

  /// From a URL's `min`, `max` and `cur`; null if neither bound reads as a
  /// non-negative number or the currency isn't one Sellora knows.
  static PriceRange? fromParameters(Map<String, String?> params) {
    double? amount(String key) {
      final v = double.tryParse(params[key]?.trim() ?? '');
      return v == null || v < 0 || !v.isFinite ? null : v;
    }

    final currency = params['cur']?.toUpperCase();
    if (currency == null || !Currencies.isSupported(currency)) return null;
    final range =
        PriceRange(min: amount('min'), max: amount('max'), currency: currency);
    return range.isEmpty ? null : range;
  }

  Map<String, String> toParameters() => {
        if (min != null) 'min': _number(min!),
        if (max != null) 'max': _number(max!),
        'cur': currency,
      };

  static String _number(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

/// One page of the store's products (TODO §20, §21): the whole shop
/// (`/s/{slug}/shop`, with category chips), one collection
/// (`/s/{slug}/collections/{handle}`), or search results
/// (`/s/{slug}/search?q=`). Each can be sorted (`sort=`) and narrowed to a
/// price range (`min=`, `max=`, `cur=`), and the shop or search to a
/// category (`category=`). Those are read from the URL and, on web,
/// written back to it, so a filtered list can be shared or refreshed.
///
/// Owned by its page (GetBuilder, not a route binding): a visitor can open
/// one collection on top of another, and each needs its own.
class ProductListController extends GetxController {
  ProductListController({
    required this.mode,
    required this.slug,
    this.handle,
    String? query,
    Map<String, String?> parameters = const {},
    StorefrontSession? session,
    ProductRepository? products,
    CurrencyService? currency,
    void Function(String path)? onPathChanged,
  })  : session = session ?? Get.find<StorefrontSession>(),
        _products = products ?? Get.find<ProductRepository>(),
        _currency = currency ?? Get.find<CurrencyService>(),
        _onPathChanged = onPathChanged ?? _replaceBrowserUrl,
        query = (query ?? '').obs,
        sort = StoreProductSort.parse(parameters['sort']).obs,
        priceRange = Rxn(PriceRange.fromParameters(parameters)),
        _initialCategory = parameters['category'];

  final ProductListMode mode;
  final String slug;

  /// The collection's URL segment, for [ProductListMode.collection].
  final String? handle;
  final StorefrontSession session;
  final ProductRepository _products;
  final CurrencyService _currency;
  final void Function(String path) _onPathChanged;
  final String? _initialCategory;

  final items = <ProductModel>[].obs;
  final isLoading = true.obs;
  final isLoadingMore = false.obs;
  final hasMore = false.obs;
  final error = RxnString();
  final RxString query;
  final Rx<StoreProductSort> sort;
  final Rxn<PriceRange> priceRange;

  /// The category shown: the collection's, or the shop's chip ('All' for
  /// none).
  final category = 'All'.obs;

  /// A collection handle that matches none of the store's categories.
  final notFound = false.obs;

  /// The currency the store's listings are priced in, which a price range
  /// is converted into before it's sent. Learned from the first product
  /// seen.
  String? _listingCurrency;

  Timer? _debounce;

  @override
  void onInit() {
    super.onInit();
    _start();
  }

  @override
  void onClose() {
    _debounce?.cancel();
    super.onClose();
  }

  Future<void> _start() async {
    await session.ensure(slug);
    if (mode == ProductListMode.collection) {
      final name = session.categoryForHandle(handle ?? '');
      if (name == null) {
        notFound.value = true;
        isLoading.value = false;
        return;
      }
      category.value = name;
    } else if (_initialCategory case final wanted?) {
      // Only one the store has: there'd be no chip to clear another.
      final name = session.categories
          .firstWhereOrNull((c) => c.toLowerCase() == wanted.toLowerCase());
      if (name != null) category.value = name;
    }
    await load();
  }

  String get title => switch (mode) {
        ProductListMode.shop => 'Shop all',
        ProductListMode.collection => category.value,
        ProductListMode.search => 'Search',
      };

  /// The shop and search offer category chips; a collection is one
  /// category already.
  bool get canPickCategory => mode != ProductListMode.collection;

  /// How many filters narrow the list, for the Filter button's badge.
  int get activeFilterCount =>
      (priceRange.value == null ? 0 : 1) +
      (canPickCategory && category.value != 'All' ? 1 : 0);

  /// This page's URL with its current search, sort and filters.
  String get currentPath {
    final base = switch (mode) {
      ProductListMode.shop => StorefrontPaths.shop,
      ProductListMode.search => StorefrontPaths.search,
      ProductListMode.collection =>
        '${StorefrontPaths.collections}/${handle ?? ''}',
    };
    final params = <String, String>{
      if (mode == ProductListMode.search && query.value.trim().isNotEmpty)
        'q': query.value.trim(),
      if (canPickCategory && category.value != 'All')
        'category': category.value,
      if (sort.value != StoreProductSort.newest) 'sort': sort.value.param,
      ...?priceRange.value?.toParameters(),
    };
    final path = session.path(base);
    return params.isEmpty
        ? path
        : Uri(path: path, queryParameters: params).toString();
  }

  /// [priceRange]'s bounds in the listings' currency, at today's rate.
  Future<(double?, double?)> _priceBounds() async {
    final range = priceRange.value;
    if (range == null) return (null, null);
    final store = session.store!;
    final listing = _listingCurrency ??=
        (await _products.storeProducts(store.id, limit: 1))
                .firstOrNull
                ?.currency ??
            store.currencyCode;
    double? convert(double? v) => v == null || range.currency == listing
        ? v
        : _currency
            .convertMoney(Money.fromMajor(v, range.currency), listing)
            .toMajor();

    return (convert(range.min), convert(range.max));
  }

  Future<List<ProductModel>> _fetch({int offset = 0}) async {
    final store = session.store!;
    final (minPrice, maxPrice) = await _priceBounds();
    final page = await _products.storeProducts(store.id,
        keyword: query.value.trim(),
        category: category.value,
        sort: sort.value,
        minPrice: minPrice,
        maxPrice: maxPrice,
        offset: offset);
    if (page.isNotEmpty) _listingCurrency ??= page.first.currency;
    return page;
  }

  Future<void> load() async {
    final store = session.store;
    if (store == null) return;
    // Search waits for a query rather than listing everything.
    if (mode == ProductListMode.search && query.value.trim().isEmpty) {
      items.clear();
      hasMore.value = false;
      isLoading.value = false;
      return;
    }
    isLoading.value = true;
    error.value = null;
    try {
      final page = await _fetch();
      items.assignAll(page);
      hasMore.value = page.length == storefrontPageSize;
    } catch (e) {
      debugPrint('ProductListController.load: $e');
      error.value = 'Couldn\'t load products. Please try again.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    final store = session.store;
    if (store == null || !hasMore.value || isLoadingMore.value) return;
    isLoadingMore.value = true;
    try {
      final page = await _fetch(offset: items.length);
      items.addAll(page);
      hasMore.value = page.length == storefrontPageSize;
    } catch (e) {
      debugPrint('ProductListController.loadMore: $e');
    } finally {
      isLoadingMore.value = false;
    }
  }

  /// Searches as the visitor types, once they pause.
  void search(String text) {
    query.value = text;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _changed);
  }

  void selectCategory(String name) {
    category.value = name;
    _changed();
  }

  void setSort(StoreProductSort value) {
    if (value == sort.value) return;
    sort.value = value;
    _changed();
  }

  /// [min]/[max] in the visitor's display currency; both null clears the
  /// range. Typed the wrong way round, they're swapped.
  void setPriceRange(double? min, double? max) {
    if (min != null && max != null && min > max) (min, max) = (max, min);
    final range =
        PriceRange(min: min, max: max, currency: _currency.code.value);
    priceRange.value = range.isEmpty ? null : range;
    _changed();
  }

  void clearFilters() {
    priceRange.value = null;
    if (canPickCategory) category.value = 'All';
    _changed();
  }

  void _changed() {
    _onPathChanged(currentPath);
    load();
  }

  /// Rewrites the address bar without navigating (web only).
  static void _replaceBrowserUrl(String path) {
    if (!kIsWeb) return;
    SystemNavigator.routeInformationUpdated(
        uri: Uri.parse(path), replace: true);
  }
}

/// `/s/{slug}/shop`, `/s/{slug}/collections/{handle}` and
/// `/s/{slug}/search`.
class ProductListPage extends StatelessWidget {
  const ProductListPage({super.key, required this.mode});
  final ProductListMode mode;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ProductListController>(
      global: false,
      init: ProductListController(
        mode: mode,
        slug: Get.parameters['slug'] ?? '',
        handle: Get.parameters['handle'],
        query: Get.parameters['q'],
        parameters: Get.parameters,
      ),
      builder: (c) => Obx(() => StorefrontPage(
            title: c.notFound.value ? 'Not found' : c.title,
            onRefresh: c.load,
            slivers: (context, store, design) => [
              SliverToBoxAdapter(child: _Header(controller: c)),
              ..._grid(context, c),
            ],
          )),
    );
  }

  List<Widget> _grid(BuildContext context, ProductListController c) {
    final h = context.pageHorizontalPadding;
    final style = StoreStyle.of(context);
    final session = c.session;
    return [
      Obx(() {
        if (c.notFound.value) {
          return SliverToBoxAdapter(
            child: EmptyState(
              icon: Icons.collections_bookmark_outlined,
              title: 'This collection isn\'t here',
              message: 'It may have been renamed, or its products are no '
                  'longer for sale.',
              actionLabel: 'See all collections',
              onAction: () =>
                  Get.offNamed(session.path(StorefrontPaths.collections)),
            ),
          );
        }
        if (c.isLoading.value) {
          return const SliverToBoxAdapter(
              child: SizedBox(height: 240, child: AppLoadingState()));
        }
        if (c.error.value case final error?) {
          return SliverToBoxAdapter(
              child: AppErrorState(message: error, onRetry: c.load));
        }
        final items = List.of(c.items);
        if (items.isEmpty && c.activeFilterCount > 0) {
          return SliverToBoxAdapter(
            child: EmptyState(
              icon: Icons.filter_alt_off_outlined,
              title: 'Nothing matches these filters',
              message: 'Try a wider price range or another category.',
              actionLabel: 'Clear filters',
              onAction: c.clearFilters,
            ),
          );
        }
        if (items.isEmpty) {
          final searching = c.mode == ProductListMode.search;
          return SliverToBoxAdapter(
            child: EmptyState(
              icon: searching ? Icons.search : Icons.inventory_2_outlined,
              title: searching
                  ? (c.query.value.trim().isEmpty
                      ? 'What are you looking for?'
                      : 'Nothing matches "${c.query.value.trim()}"')
                  : 'No products here yet',
              message:
                  searching ? 'Search by product name.' : 'Check back soon.',
            ),
          );
        }
        return SliverPadding(
          padding: EdgeInsets.fromLTRB(h, AppSpacing.md, h, AppSpacing.md),
          sliver: SliverGrid(
            gridDelegate: productGridDelegate(
                childAspectRatio: style.productCard.tileAspectRatio),
            delegate: SliverChildBuilderDelegate(
              (context, i) => ProductCard(
                product: items[i],
                style: style.productCard,
                onTap: () => Get.toNamed(
                    session.path(StorefrontPaths.product(items[i].id)),
                    arguments: items[i]),
              ),
              childCount: items.length,
            ),
          ),
        );
      }),
      Obx(() {
        if (c.isLoading.value || !c.hasMore.value) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        return SliverToBoxAdapter(
          child: Center(
            child: c.isLoadingMore.value
                ? const CircularProgressIndicator()
                : OutlinedButton(
                    onPressed: c.loadMore, child: const Text('Load more')),
          ),
        );
      }),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});
  final ProductListController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final style = StoreStyle.of(context);
    final textTheme = Theme.of(context).textTheme;
    final h = context.pageHorizontalPadding;
    return Padding(
      padding: EdgeInsets.fromLTRB(h, AppSpacing.lg, h, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.mode == ProductListMode.search)
            _SearchField(controller: c)
          else
            Obx(() {
              c.category.value; // a collection's title is its category
              return Text(style.heading(c.title),
                  style: style.headingStyle(textTheme.headlineSmall));
            }),
          if (c.canPickCategory)
            Obx(() {
              final categories = ['All', ...c.session.categories];
              if (categories.length < 2) return const SizedBox.shrink();
              final scheme = Theme.of(context).colorScheme;
              return Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final name in categories)
                      ChoiceChip(
                        label: Text(name),
                        selected: c.category.value == name,
                        selectedColor: scheme.primary,
                        labelStyle: TextStyle(
                            color: c.category.value == name
                                ? scheme.onPrimary
                                : scheme.onSurface),
                        onSelected: (_) => c.selectCategory(name),
                      ),
                  ],
                ),
              );
            }),
          _Toolbar(controller: c),
        ],
      ),
    );
  }
}

/// Price filter on the left, sort on the right.
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller});
  final ProductListController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Obx(() {
        final range = c.priceRange.value;
        // Each side shrinks (ellipsized) rather than overflow a narrow
        // phone.
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Align(
                alignment: Alignment.centerLeft,
                child: range == null
                    ? OutlinedButton.icon(
                        key: const ValueKey('product-price-filter'),
                        onPressed: () => _editPrice(context),
                        icon: const Icon(Icons.tune, size: 18),
                        label: const Text('Price'),
                      )
                    : InputChip(
                        key: const ValueKey('product-price-filter'),
                        label: Text(priceRangeLabel(range),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        onPressed: () => _editPrice(context),
                        onDeleted: () => c.setPriceRange(null, null),
                        deleteButtonTooltipMessage: 'Remove price filter',
                      ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: PopupMenuButton<StoreProductSort>(
                key: const ValueKey('product-sort'),
                tooltip: 'Sort',
                initialValue: c.sort.value,
                onSelected: c.setSort,
                itemBuilder: (_) => [
                  for (final s in StoreProductSort.values)
                    PopupMenuItem(value: s, child: Text(s.label)),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sort, size: 18),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(c.sort.value.label,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _editPrice(BuildContext context) async {
    final range = await showModalBottomSheet<(double?, double?)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PriceSheet(range: controller.priceRange.value),
    );
    if (range != null) controller.setPriceRange(range.$1, range.$2);
  }
}

/// "KSh 500 – KSh 2,000", "From KSh 500" or "Up to KSh 2,000", in the
/// currency the range was typed in.
String priceRangeLabel(PriceRange range) {
  String money(double v) =>
      Formatters.money(Money.fromMajor(v, range.currency));
  return switch ((range.min, range.max)) {
    (final min?, final max?) => '${money(min)} – ${money(max)}',
    (final min?, null) => 'From ${money(min)}',
    (null, final max?) => 'Up to ${money(max)}',
    (null, null) => 'Any price',
  };
}

/// Min and max price, in the visitor's display currency. Pops
/// `(min, max)`, both null to clear, or nothing if dismissed.
class _PriceSheet extends StatefulWidget {
  const _PriceSheet({required this.range});
  final PriceRange? range;

  @override
  State<_PriceSheet> createState() => _PriceSheetState();
}

class _PriceSheetState extends State<_PriceSheet> {
  final _currency = Get.find<CurrencyService>().code.value;

  /// A range typed in another currency is shown converted into this one.
  late final _min = TextEditingController(text: _start(widget.range?.min));
  late final _max = TextEditingController(text: _start(widget.range?.max));

  String _start(double? v) {
    final range = widget.range;
    if (v == null || range == null) return '';
    final amount = range.currency == _currency
        ? v
        : Get.find<CurrencyService>()
            .convertMoney(Money.fromMajor(v, range.currency), _currency)
            .toMajor();
    return amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  static double? _parse(String text) {
    final v = double.tryParse(text.replaceAll(',', '').trim());
    return v == null || v < 0 ? null : v;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    InputDecoration field(String label) => InputDecoration(
        labelText: label, prefixText: '${Currencies.of(_currency).symbol} ');
    final digits = [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Price', style: textTheme.titleLarge),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('price-min'),
                  controller: _min,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: digits,
                  decoration: field('Min'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextField(
                  key: const ValueKey('price-max'),
                  controller: _max,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: digits,
                  decoration: field('Max'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, (null, null)),
                child: const Text('Clear'),
              ),
              const Spacer(),
              ElevatedButton(
                key: const ValueKey('price-apply'),
                onPressed: () => Navigator.pop(
                    context, (_parse(_min.text), _parse(_max.text))),
                child: const Text('Show results'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.controller});
  final ProductListController controller;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final _text = TextEditingController(text: widget.controller.query.value);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _text,
        autofocus: _text.text.isEmpty,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search this store',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.close),
            onPressed: () {
              _text.clear();
              widget.controller.search('');
            },
          ),
        ),
        onChanged: widget.controller.search,
        onSubmitted: widget.controller.search,
      );
}

/// `/s/{slug}/collections`: a tile per category with products, using the
/// image the seller gave that category in a Collections section, if any.
class CollectionsPage extends StatelessWidget {
  const CollectionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Get.find<StorefrontSession>();
    return StorefrontPage(
      title: 'Collections',
      onRefresh: session.reload,
      slivers: (context, store, design) {
        final style = StoreStyle.of(context);
        final textTheme = Theme.of(context).textTheme;
        final images = _imagesByCategory(design);
        return [
          SliverToBoxAdapter(
            child: StorefrontContent(
              child: Obx(() {
                final categories = List.of(session.categories);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(style.heading('Collections'),
                        style: style.headingStyle(textTheme.headlineSmall)),
                    const SizedBox(height: AppSpacing.md),
                    if (categories.isEmpty)
                      const EmptyState(
                        icon: Icons.collections_bookmark_outlined,
                        title: 'No collections yet',
                        message: 'Products will be grouped here as they '
                            'are added.',
                      )
                    else
                      LayoutBuilder(builder: (context, constraints) {
                        final columns =
                            (constraints.maxWidth / 220).floor().clamp(2, 5);
                        final width = (constraints.maxWidth -
                                AppSpacing.sm * (columns - 1)) /
                            columns;
                        return Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.md,
                          children: [
                            for (final name in categories)
                              SizedBox(
                                width: width,
                                child: _CollectionTile(
                                  name: name,
                                  imageUrl: images[name.toLowerCase()],
                                  onTap: () => Get.toNamed(session
                                      .path(StorefrontPaths.collection(name))),
                                ),
                              ),
                          ],
                        );
                      }),
                  ],
                );
              }),
            ),
          ),
        ];
      },
    );
  }

  /// Category (lower-cased) → the image a Collections section gave it.
  static Map<String, String> _imagesByCategory(StoreDesign design) => {
        for (final section in design.sections)
          if (section.type == SectionType.collectionList)
            for (final block in section.blocks)
              if ((block.settings['category'], block.settings['imageUrl'])
                  case (final String c, final String url))
                c.trim().toLowerCase(): url,
      };
}

class _CollectionTile extends StatelessWidget {
  const _CollectionTile(
      {required this.name, required this.imageUrl, required this.onTap});
  final String name;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = StoreStyle.of(context);
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(style.smallRadius);
    final placeholder = ColoredBox(
      color: scheme.primary.withValues(alpha: 0.12),
      child: Center(
        child: Text(name.characters.first.toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .displaySmall
                ?.copyWith(color: scheme.primary)),
      ),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: radius,
            child: AspectRatio(
              aspectRatio: 1,
              child: imageUrl == null
                  ? placeholder
                  : CachedNetworkImage(
                      imageUrl: imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => placeholder,
                      errorWidget: (_, __, ___) => placeholder,
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(name, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}
