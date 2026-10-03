import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/image_data_url.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/store_design.dart';
import '../../../data/models/store_theme.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/repositories/store_design_repository.dart';
import '../../../data/repositories/store_repository.dart';
import '../../storefront/store_scope.dart';

/// Which editor the builder's side panel shows.
sealed class BuilderPanel {
  const BuilderPanel();
}

class RootPanel extends BuilderPanel {
  const RootPanel();
}

class ThemePanel extends BuilderPanel {
  const ThemePanel();
}

/// The theme gallery (TODO §19), reached from [ThemePanel].
class ThemeLibraryPanel extends BuilderPanel {
  const ThemeLibraryPanel();
}

class AnnouncementPanel extends BuilderPanel {
  const AnnouncementPanel();
}

class NavigationPanel extends BuilderPanel {
  const NavigationPanel();
}

class FooterPanel extends BuilderPanel {
  const FooterPanel();
}

class SectionPanel extends BuilderPanel {
  const SectionPanel(this.sectionId);
  final String sectionId;
}

class BlockPanel extends BuilderPanel {
  const BlockPanel(this.sectionId, this.blockId);
  final String sectionId;
  final String blockId;
}

enum PreviewDevice { desktop, mobile }

/// The store builder (TODO §18, themes §19): edits a working copy of the store's
/// design, saves it as the draft, and publishes the draft to the live
/// storefront. The preview renders the working copy with the storefront's
/// own renderer.
class StoreBuilderController extends GetxController {
  StoreBuilderController({
    StoreScope? scope,
    StoreDesignRepository? designs,
    StoreRepository? stores,
    ProductRepository? products,
  })  : scope = scope ?? Get.find<StoreScope>(),
        _designs = designs ?? Get.find<StoreDesignRepository>(),
        _stores = stores ?? Get.find<StoreRepository>(),
        _products = products ?? Get.find<ProductRepository>();

  static const previewTag = 'store-builder-preview';

  final StoreScope scope;
  final StoreDesignRepository _designs;
  final StoreRepository _stores;
  final ProductRepository _products;

  /// The working copy the panels edit and the preview shows.
  final design = Rxn<StoreDesign>();
  final record = Rxn<StoreDesignRecord>();

  /// The draft as last saved (or loaded), to tell whether there are
  /// unsaved changes.
  final _savedJson = RxnString();

  final panel = Rx<BuilderPanel>(const RootPanel());
  final device = PreviewDevice.desktop.obs;
  final isLoading = true.obs;
  final isSaving = false.obs;
  final isPublishing = false.obs;
  final loadError = RxnString();

  /// The setting key an image is being uploaded for.
  final uploadingKey = RxnString();

  final subscribers = <NewsletterSubscriber>[].obs;
  final pickerProducts = <ProductModel>[].obs;

  final _picker = ImagePicker();

  String? get storeId => scope.current.value?.id;

  bool get isDirty {
    final d = design.value;
    return d != null && jsonEncode(d.toMap()) != _savedJson.value;
  }

  /// The saved draft differs from what's live (or nothing is live yet).
  bool get hasUnpublishedChanges {
    final r = record.value;
    if (r == null || r.published == null) return true;
    return _savedJson.value != jsonEncode(r.published!.toMap());
  }

  String? get selectedSectionId => switch (panel.value) {
        SectionPanel(:final sectionId) => sectionId,
        BlockPanel(:final sectionId) => sectionId,
        _ => null,
      };

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    final store = scope.current.value;
    if (store == null) {
      loadError.value = 'Your store isn\'t loaded yet.';
      isLoading.value = false;
      return;
    }
    isLoading.value = true;
    loadError.value = null;
    try {
      final r = await _designs.loadForOwner(store.id);
      record.value = r;
      final draft = r?.draft;
      final start = draft != null && draft.sections.isNotEmpty
          ? draft
          : r?.published ?? StoreDesign.starter(store);
      design.value = start;
      // A store that never saved a design starts "dirty", so Save and
      // Publish are offered straight away.
      _savedJson.value = r == null ? null : jsonEncode(r.draft.toMap());
    } catch (e) {
      debugPrint('StoreBuilderController.load: $e');
      loadError.value = 'Couldn\'t load your store design.';
    } finally {
      isLoading.value = false;
    }
  }

  void open(BuilderPanel p) => panel.value = p;

  void back() => panel.value = switch (panel.value) {
        BlockPanel(:final sectionId) => SectionPanel(sectionId),
        ThemeLibraryPanel() => const ThemePanel(),
        _ => const RootPanel(),
      };

  void _edit(StoreDesign Function(StoreDesign d) change) {
    final d = design.value;
    if (d == null) return;
    design.value = change(d);
    // Undoing a theme now would throw this edit away too.
    beforeTheme.value = null;
  }

  // ---- Theme, announcement, menu, footer ---------------------------------

  void setTheme(ThemeSettings theme) => _edit((d) => d.copyWith(theme: theme));

  void applyPalette(ThemePalette p) => _edit((d) => d.copyWith(
      theme: d.theme.copyWith(
          accentHex: p.accent,
          backgroundHex: p.background,
          surfaceHex: p.surface,
          textHex: p.text)));

  // ---- Themes ---------------------------------------------------------------

  /// The design as it was before the last [applyTheme], for [undoTheme].
  final beforeTheme = Rxn<StoreDesign>();

  StoreTheme get currentTheme =>
      StoreTheme.byId(design.value?.themeId ?? StoreDesign.defaultThemeId);

  /// The theme to suggest for this store's category.
  StoreTheme get suggestedTheme =>
      StoreTheme.suggestedFor(scope.current.value?.category);

  /// Restyles the working copy with [theme]; with [homepage], also swaps
  /// the homepage sections for the theme's starter layout. Nothing is
  /// saved, and [undoTheme] puts the previous design back.
  void applyTheme(StoreTheme theme, {bool homepage = false}) {
    final d = design.value;
    final store = scope.current.value;
    if (d == null || store == null) return;
    beforeTheme.value = d;
    design.value = theme.applyTo(d, store: store, homepage: homepage);
    // A section being edited may be gone.
    if (homepage) open(const ThemePanel());
  }

  void undoTheme() {
    final before = beforeTheme.value;
    if (before == null) return;
    design.value = before;
    beforeTheme.value = null;
  }

  void setAnnouncement(AnnouncementBar bar) =>
      _edit((d) => d.copyWith(announcement: bar));

  void setNavigation(List<StoreLink> links) => _edit((d) =>
      d.copyWith(navigation: links.take(StoreDesign.maxNavLinks).toList()));

  void setFooter(FooterSettings footer) =>
      _edit((d) => d.copyWith(footer: footer));

  // ---- Sections -----------------------------------------------------------

  bool canAdd(SectionType type) {
    final d = design.value;
    if (d == null || d.sections.length >= StoreDesign.maxSections) return false;
    return !type.isSingleton || !d.sections.any((s) => s.type == type);
  }

  /// Adds a [type] section above the catalog (or at the end if there is
  /// none) and opens it.
  void addSection(SectionType type) {
    if (!canAdd(type)) return;
    final section = StoreSection.create(type);
    _edit((d) {
      final list = [...d.sections];
      final catalogAt = list.indexWhere((s) => s.type == SectionType.catalog);
      list.insert(catalogAt < 0 ? list.length : catalogAt, section);
      return d.copyWith(sections: list);
    });
    open(SectionPanel(section.id));
  }

  /// The catalog can't be removed: it's how buyers reach every product.
  bool canRemove(StoreSection section) => section.type != SectionType.catalog;

  void removeSection(String id) {
    final section = design.value?.sectionById(id);
    if (section == null || !canRemove(section)) return;
    _edit((d) =>
        d.copyWith(sections: d.sections.where((s) => s.id != id).toList()));
    if (selectedSectionId == id) open(const RootPanel());
  }

  void duplicateSection(String id) {
    final d = design.value;
    final section = d?.sectionById(id);
    if (d == null || section == null || !canAdd(section.type)) return;
    final copy = StoreSection(
      id: newDesignId(section.type.id),
      type: section.type,
      enabled: section.enabled,
      settings: Map.of(section.settings),
      blocks: [
        for (final b in section.blocks)
          SectionBlock(
              id: newDesignId(b.type),
              type: b.type,
              settings: Map.of(b.settings)),
      ],
    );
    final list = [...d.sections];
    list.insert(list.indexWhere((s) => s.id == id) + 1, copy);
    design.value = d.copyWith(sections: list);
  }

  /// ReorderableListView's indices: [newIndex] counts the moved item.
  void moveSection(int oldIndex, int newIndex) => _edit((d) {
        final list = [...d.sections];
        final item = list.removeAt(oldIndex);
        list.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);
        return d.copyWith(sections: list);
      });

  void toggleSection(String id) =>
      _updateSection(id, (s) => s.copyWith(enabled: !s.enabled));

  void setSectionSetting(String id, String key, Object? value) =>
      _updateSection(id, (s) {
        final def = s.type.settings.firstWhere((d) => d.key == key);
        return s.copyWith(settings: {...s.settings, key: def.read(value)});
      });

  void _updateSection(String id, StoreSection Function(StoreSection) change) =>
      _edit((d) {
        final s = d.sectionById(id);
        return s == null ? d : d.withSection(change(s));
      });

  // ---- Blocks -------------------------------------------------------------

  void addBlock(String sectionId) {
    final section = design.value?.sectionById(sectionId);
    final schema = section?.type.blocks;
    if (section == null ||
        schema == null ||
        section.blocks.length >= schema.max) {
      return;
    }
    final block = StoreSection.newBlock(schema);
    _updateSection(sectionId, (s) => s.copyWith(blocks: [...s.blocks, block]));
    open(BlockPanel(sectionId, block.id));
  }

  bool canRemoveBlock(StoreSection section) =>
      section.blocks.length > (section.type.blocks?.min ?? 0);

  void removeBlock(String sectionId, String blockId) {
    final section = design.value?.sectionById(sectionId);
    if (section == null || !canRemoveBlock(section)) return;
    _updateSection(
        sectionId,
        (s) => s.copyWith(
            blocks: s.blocks.where((b) => b.id != blockId).toList()));
    if (panel.value is BlockPanel) open(SectionPanel(sectionId));
  }

  void moveBlock(String sectionId, int from, int to) =>
      _updateSection(sectionId, (s) {
        if (to < 0 || to >= s.blocks.length) return s;
        final list = [...s.blocks];
        list.insert(to, list.removeAt(from));
        return s.copyWith(blocks: list);
      });

  void setBlockSetting(
          String sectionId, String blockId, String key, Object? value) =>
      _updateSection(sectionId, (s) {
        final schema = s.type.blocks!;
        final def = schema.settings.firstWhere((d) => d.key == key);
        return s.copyWith(blocks: [
          for (final b in s.blocks)
            b.id == blockId
                ? b.copyWith(settings: {...b.settings, key: def.read(value)})
                : b,
        ]);
      });

  // ---- Images and products ------------------------------------------------

  /// Picks a photo and uploads it to the store's media folder. Returns its
  /// URL, or null if cancelled or it failed (the seller is told why).
  Future<String?> uploadImage(String key) async {
    final id = storeId;
    if (id == null) return null;
    uploadingKey.value = key;
    try {
      final picked = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 85, maxWidth: 2000);
      if (picked == null) return null;
      final bytes = await picked.readAsBytes();
      if (bytes.lengthInBytes > maxPickedImageBytes) {
        Get.snackbar('Image too large',
            'Choose a photo under ${maxPickedImageBytes ~/ (1024 * 1024)}MB.');
        return null;
      }
      return await _stores.uploadStoreImage(id, bytes,
          contentType: picked.mimeType ?? mimeTypeForPath(picked.path),
          kind: 'design');
    } catch (e) {
      debugPrint('StoreBuilderController.uploadImage: $e');
      Get.snackbar('Upload failed',
          'The photo could not be uploaded. Check your connection and try again.');
      return null;
    } finally {
      uploadingKey.value = null;
    }
  }

  /// The listed products a featured section can pick from.
  Future<void> loadPickerProducts() async {
    final id = storeId;
    if (id == null) return;
    try {
      pickerProducts.value = await _products.storeProducts(id, limit: 200);
    } catch (e) {
      debugPrint('StoreBuilderController.loadPickerProducts: $e');
    }
  }

  // ---- Newsletter ---------------------------------------------------------

  Future<void> loadSubscribers() async {
    final id = storeId;
    if (id == null) return;
    try {
      subscribers.value = await _designs.subscribers(id);
    } catch (e) {
      debugPrint('StoreBuilderController.loadSubscribers: $e');
    }
  }

  Future<void> removeSubscriber(NewsletterSubscriber s) async {
    try {
      await _designs.removeSubscriber(s.id);
      subscribers.remove(s);
    } catch (e) {
      debugPrint('StoreBuilderController.removeSubscriber: $e');
      Get.snackbar('Couldn\'t remove', 'Please try again.');
    }
  }

  // ---- Save / publish -----------------------------------------------------

  /// Saves the working copy as the draft. Returns whether it worked.
  Future<bool> saveDraft({bool quiet = false}) async {
    final id = storeId;
    final d = design.value;
    if (id == null || d == null) return false;
    isSaving.value = true;
    try {
      await _designs.saveDraft(id, d);
      _savedJson.value = jsonEncode(d.toMap());
      if (!quiet) Get.snackbar('Draft saved', 'Publish when you\'re ready.');
      return true;
    } catch (e) {
      debugPrint('StoreBuilderController.saveDraft: $e');
      Get.snackbar('Couldn\'t save', 'Check your connection and try again.');
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  /// Saves, then publishes. Returns the problems that stopped it (empty
  /// when it was published or failed for another reason, which the seller
  /// is told about).
  Future<List<String>> publish() async {
    final id = storeId;
    final d = design.value;
    if (id == null || d == null) return const [];
    final problems = d.problems();
    if (problems.isNotEmpty) return problems;
    isPublishing.value = true;
    try {
      if (!await saveDraft(quiet: true)) return const [];
      final version = await _designs.publish(id);
      record.value = await _designs.loadForOwner(id);
      // publish_store_design copied the accent onto the store; keep the
      // in-memory store in step so Store details doesn't write back the
      // old one.
      final store = scope.current.value;
      if (store != null) {
        scope.current.value =
            store.copyWith(primaryColorHex: d.theme.accentHex);
      }
      Get.snackbar('Published', 'Version $version of your storefront is live.');
    } catch (e) {
      debugPrint('StoreBuilderController.publish: $e');
      Get.snackbar('Couldn\'t publish', 'Please try again.');
    } finally {
      isPublishing.value = false;
    }
    return const [];
  }

  /// Drops edits since the last save.
  void discardChanges() {
    final saved = _savedJson.value;
    final store = scope.current.value;
    if (saved != null) {
      design.value =
          StoreDesign.fromMap(jsonDecode(saved) as Map<String, dynamic>);
    } else if (store != null) {
      design.value = StoreDesign.starter(store);
    }
    beforeTheme.value = null;
    open(const RootPanel());
  }

  /// Puts the live design back into the editor (save to make it the draft).
  void revertToPublished() {
    final published = record.value?.published;
    if (published == null) return;
    design.value = published;
    beforeTheme.value = null;
    open(const RootPanel());
  }
}
