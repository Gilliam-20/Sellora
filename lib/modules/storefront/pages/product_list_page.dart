import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/app_page.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/product_card.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/store_design.dart';
import '../../../data/repositories/product_repository.dart';
import '../design/storefront_theme.dart';
import '../shell/storefront_links.dart';
import '../shell/storefront_page.dart';
import '../storefront_session.dart';

enum ProductListMode { shop, collection, search }

/// One page of the store's products, filtered (TODO §20): the whole shop
/// (`/s/{slug}/shop`, with category chips), one collection
/// (`/s/{slug}/collections/{handle}`), or search results
/// (`/s/{slug}/search?q=`).
///
/// Owned by its page (GetBuilder, not a route binding): a visitor can open
/// one collection on top of another, and each needs its own.
class ProductListController extends GetxController {
  ProductListController({
    required this.mode,
    required this.slug,
    this.handle,
    String? query,
    StorefrontSession? session,
    ProductRepository? products,
  })  : session = session ?? Get.find<StorefrontSession>(),
        _products = products ?? Get.find<ProductRepository>(),
        query = (query ?? '').obs;

  final ProductListMode mode;
  final String slug;

  /// The collection's URL segment, for [ProductListMode.collection].
  final String? handle;
  final StorefrontSession session;
  final ProductRepository _products;

  final items = <ProductModel>[].obs;
  final isLoading = true.obs;
  final isLoadingMore = false.obs;
  final hasMore = false.obs;
  final error = RxnString();
  final RxString query;

  /// The category shown: the collection's, or the shop's chip ('All' for
  /// none).
  final category = 'All'.obs;

  /// A collection handle that matches none of the store's categories.
  final notFound = false.obs;

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
    }
    await load();
  }

  String get title => switch (mode) {
        ProductListMode.shop => 'Shop all',
        ProductListMode.collection => category.value,
        ProductListMode.search => 'Search',
      };

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
      final page = await _products.storeProducts(store.id,
          keyword: query.value.trim(), category: category.value);
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
      final page = await _products.storeProducts(store.id,
          keyword: query.value.trim(),
          category: category.value,
          offset: items.length);
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
    _debounce = Timer(const Duration(milliseconds: 350), load);
  }

  void selectCategory(String name) {
    category.value = name;
    load();
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
          if (c.mode == ProductListMode.shop)
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
