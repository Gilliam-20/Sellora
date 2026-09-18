import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/utils/color_utils.dart';
import '../../../data/repositories/store_repository.dart';
import '../../storefront/store_scope.dart';

/// Lets a seller edit the branding fields their [StoreModel] already
/// carries (name, tagline, logo, banner, accent color) — the first slice of
/// Phase 6's Store Builder. Sections/blocks/themes are a separate, larger
/// piece of work; this is scoped to what `StoreModel` already stores.
class StoreCustomizeController extends GetxController {
  StoreCustomizeController({StoreScope? scope, StoreRepository? repository})
      : scope = scope ?? Get.find<StoreScope>(),
        _storeRepository = repository ?? Get.find<StoreRepository>();

  final StoreScope scope;
  final StoreRepository _storeRepository;

  late final TextEditingController nameCtrl;
  late final TextEditingController taglineCtrl;
  late final TextEditingController logoUrlCtrl;
  late final TextEditingController bannerUrlCtrl;
  late final TextEditingController hexCtrl;

  final colorHex = RxnString();
  final isSaving = false.obs;

  @override
  void onInit() {
    super.onInit();
    final store = scope.current.value;
    nameCtrl = TextEditingController(text: store?.name);
    taglineCtrl = TextEditingController(text: store?.tagline);
    logoUrlCtrl = TextEditingController(text: store?.logoUrl);
    bannerUrlCtrl = TextEditingController(text: store?.bannerUrl);
    colorHex.value = store?.primaryColorHex;
    hexCtrl = TextEditingController(text: store?.primaryColorHex);
  }

  @override
  void onClose() {
    nameCtrl.dispose();
    taglineCtrl.dispose();
    logoUrlCtrl.dispose();
    bannerUrlCtrl.dispose();
    hexCtrl.dispose();
    super.onClose();
  }

  void selectPreset(String hex) {
    colorHex.value = hex;
    hexCtrl.text = hex;
  }

  void setHexFromField(String value) {
    colorHex.value = value.trim().isEmpty ? null : value.trim();
  }

  Future<bool> save() async {
    final store = scope.current.value;
    if (store == null) return false;
    isSaving.value = true;
    try {
      final hex = colorHex.value?.trim();
      // copyWith's `?? this.field` pattern means null leaves a field
      // unchanged — only pass a hex once it's valid, otherwise keep whatever
      // color the store already had.
      final validHex = hex != null && hexToColor(hex) != null ? hex : null;
      final updated = store.copyWith(
        name: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
        tagline: taglineCtrl.text.trim(),
        logoUrl: logoUrlCtrl.text.trim(),
        bannerUrl: bannerUrlCtrl.text.trim(),
        primaryColorHex: validHex,
      );
      await _storeRepository.updateStore(updated);
      scope.current.value = updated;
      return true;
    } finally {
      isSaving.value = false;
    }
  }
}
