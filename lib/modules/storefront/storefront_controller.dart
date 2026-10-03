import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../data/models/product_model.dart';
import '../../data/models/store_design.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/repositories/store_design_repository.dart';
import 'store_scope.dart';

/// The homepage's data: the catalog section's products (search, category,
/// paging), the featured sections' products and newsletter sign-ups. The
/// design itself comes from StorefrontSession, or from the builder in the
/// preview.
class StorefrontController extends GetxController {
  /// [previewMode] is the store builder's preview: nothing is added to the
  /// newsletter list.
  StorefrontController({this.previewMode = false});

  final bool previewMode;
  final StoreScope scope = Get.find<StoreScope>();
  final ProductRepository _products = Get.find<ProductRepository>();

  final items = <ProductModel>[].obs;
  final isLoading = true.obs;

  /// Featured-section products, keyed by [_featuredKey].
  final featured = <String, List<ProductModel>>{}.obs;
  final _featuredLoading = <String>{};

  /// Whether the last page came back full, so another may exist.
  final hasMore = false.obs;
  final isLoadingMore = false.obs;
  final selectedCategory = 'All'.obs;
  final searchQuery = ''.obs;
  static const baseCategories = ['All', 'Electronics', 'Fashion', 'Home'];

  /// The filter chips: the usual ones, plus a category a collection tile
  /// or menu link opened.
  List<String> get categories => [
        ...baseCategories,
        if (!baseCategories.contains(selectedCategory.value))
          selectedCategory.value,
      ];

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// Reads the already-resolved StoreScope.current (StorefrontFrame builds
  /// the homepage only once the store is loaded), so filtering never
  /// re-triggers a slug lookup.
  Future<void> load() async {
    final store = scope.current.value;
    if (store == null) {
      items.clear();
      isLoading.value = false;
      return;
    }
    isLoading.value = true;
    final page = await _products.storeProducts(
      store.id,
      keyword: searchQuery.value,
      category: selectedCategory.value,
    );
    items.value = page;
    hasMore.value = page.length == storefrontPageSize;
    isLoading.value = false;
  }

  /// Pull to refresh: the featured sections as well as the catalog.
  Future<void> refreshAll() {
    featured.clear();
    return load();
  }

  /// Appends the next page of the current search/category.
  Future<void> loadMore() async {
    final store = scope.current.value;
    if (store == null || !hasMore.value || isLoadingMore.value) return;
    isLoadingMore.value = true;
    try {
      final page = await _products.storeProducts(
        store.id,
        keyword: searchQuery.value,
        category: selectedCategory.value,
        offset: items.length,
      );
      items.addAll(page);
      hasMore.value = page.length == storefrontPageSize;
    } finally {
      isLoadingMore.value = false;
    }
  }

  void search(String query) {
    searchQuery.value = query;
    load();
  }

  void selectCategory(String category) {
    selectedCategory.value = category;
    load();
  }

  static String _featuredKey(StoreSection section) => [
        section.settings['source'],
        section.settings['count'],
        ...(section.settings['productIds'] as List? ?? const []),
      ].join('|');

  /// The products [section] (a featured-products section) shows, or null
  /// while they load. Settings that change what's shown (the builder
  /// preview) start a new fetch.
  List<ProductModel>? featuredFor(StoreSection section) {
    final key = _featuredKey(section);
    final cached = featured[key];
    if (cached != null) return cached;
    if (_featuredLoading.add(key)) _loadFeatured(section, key);
    return null;
  }

  Future<void> _loadFeatured(StoreSection section, String key) async {
    final store = scope.current.value;
    if (store == null) return;
    final source = section.settings['source'];
    try {
      featured[key] = await _products.featuredProducts(
        store.id,
        ids: source == 'selected'
            ? List<String>.from(section.settings['productIds'] as List? ?? [])
            : null,
        bestSelling: source == 'bestSelling',
        limit: int.tryParse('${section.settings['count']}') ?? 4,
      );
    } catch (e) {
      debugPrint('StorefrontController: featured load failed: $e');
      featured[key] = const [];
    } finally {
      _featuredLoading.remove(key);
    }
  }

  /// A visitor's newsletter sign-up. Returns null on success, else a
  /// message for them.
  Future<String?> subscribe(String email) async {
    final store = scope.current.value;
    if (store == null) return 'This store is not available.';
    if (previewMode) return null;
    try {
      await Get.find<StoreDesignRepository>()
          .subscribeToNewsletter(store.id, email.trim());
      return null;
    } catch (e) {
      debugPrint('StorefrontController.subscribe: $e');
      return 'Couldn\'t sign you up. Check the address and try again.';
    }
  }
}
