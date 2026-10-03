import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../../data/models/store_page.dart';
import '../../../data/repositories/store_page_repository.dart';
import '../../storefront/store_scope.dart';

/// Seller → Store pages (TODO §20): the storefront's About, Contact and
/// policy pages. Lists the six, edits one at a time, saves it published or
/// hidden, and offers a template to start from.
class StorePagesController extends GetxController {
  StorePagesController({StoreScope? scope, StorePageRepository? repository})
      : scope = scope ?? Get.find<StoreScope>(),
        _repo = repository ?? Get.find<StorePageRepository>();

  final StoreScope scope;
  final StorePageRepository _repo;

  final pages = <StorePageKind, StorePage>{}.obs;
  final isLoading = true.obs;
  final loadError = RxnString();
  final isSaving = false.obs;

  /// The page being edited (a working copy), or null on the list.
  final editing = Rxn<StorePage>();

  String? get storeId => scope.current.value?.id;
  String get storeName => scope.current.value?.name ?? 'our store';

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    final id = storeId;
    if (id == null) {
      loadError.value = 'Your store isn\'t loaded yet.';
      isLoading.value = false;
      return;
    }
    isLoading.value = true;
    loadError.value = null;
    try {
      pages.assignAll(await _repo.ownerPages(id));
    } catch (e) {
      debugPrint('StorePagesController.load: $e');
      loadError.value = 'Couldn\'t load your pages.';
    } finally {
      isLoading.value = false;
    }
  }

  /// Opens [kind]'s saved page, or a blank one with its usual title.
  void edit(StorePageKind kind) => editing.value =
      pages[kind] ?? StorePage(kind: kind, title: kind.defaultTitle);

  void closeEditor() => editing.value = null;

  void change(StorePage page) => editing.value = page;

  /// Replaces the body with the template for this kind of page.
  void useTemplate() {
    final page = editing.value;
    if (page == null) return;
    final template = StorePageTemplates.of(page.kind, storeName);
    editing.value = page.copyWith(body: template.body);
  }

  bool get isDirty {
    final page = editing.value;
    if (page == null) return false;
    final saved = pages[page.kind];
    if (saved == null) {
      return page.body.isNotEmpty ||
          page.email != null ||
          page.phone != null ||
          page.title != page.kind.defaultTitle;
    }
    return saved.title != page.title ||
        saved.body != page.body ||
        saved.email != page.email ||
        saved.phone != page.phone ||
        saved.isPublished != page.isPublished;
  }

  /// Saves the page being edited. Returns what stopped it, empty when it
  /// saved (or failed for a reason the seller is told about).
  Future<List<String>> save() async {
    final id = storeId;
    final page = editing.value;
    if (id == null || page == null) return const [];
    final problems = page.problems();
    if (problems.isNotEmpty) return problems;
    isSaving.value = true;
    try {
      await _repo.savePage(id, page);
      pages[page.kind] = page;
      Get.snackbar(
          'Saved',
          page.isPublished
              ? '${page.title} is live on your storefront.'
              : '${page.title} is saved and hidden.');
      // Reload for the server's updated date.
      await load();
      editing.value = pages[page.kind] ?? page;
    } catch (e) {
      debugPrint('StorePagesController.save: $e');
      Get.snackbar('Couldn\'t save', 'Check your connection and try again.');
    } finally {
      isSaving.value = false;
    }
    return const [];
  }

  Future<void> delete(StorePageKind kind) async {
    final id = storeId;
    if (id == null) return;
    try {
      await _repo.deletePage(id, kind);
      pages.remove(kind);
      editing.value = null;
    } catch (e) {
      debugPrint('StorePagesController.delete: $e');
      Get.snackbar('Couldn\'t delete', 'Please try again.');
    }
  }
}
