import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/color_utils.dart';
import '../../../core/utils/image_data_url.dart';
import '../../../data/models/store_model.dart';
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

  /// Enabled `ShippingZone` ids — checkout only offers countries in these.
  final shippingZones = <String>[].obs;
  final isSaving = false.obs;
  final isPickingLogo = false.obs;
  final isPickingBanner = false.obs;

  final _picker = ImagePicker();

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
    shippingZones
        .assignAll(store?.shippingZones ?? StoreModel.allShippingZoneIds);
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

  /// Toggles zone [id] on or off. The last enabled zone can't be turned
  /// off — a store that ships nowhere would leave checkout with no country
  /// to pick. Returns false when that toggle was refused.
  bool toggleZone(String id) {
    if (shippingZones.contains(id)) {
      if (shippingZones.length == 1) return false;
      shippingZones.remove(id);
    } else {
      shippingZones.add(id);
    }
    return true;
  }

  void setHexFromField(String value) {
    colorHex.value = value.trim().isEmpty ? null : value.trim();
  }

  Future<void> pickLogo() => _pickImage(logoUrlCtrl, isPickingLogo);

  Future<void> pickBanner() => _pickImage(bannerUrlCtrl, isPickingBanner);

  Future<void> _pickImage(
      TextEditingController target, RxBool isPicking) async {
    isPicking.value = true;
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1024,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.lengthInBytes > maxPickedImageBytes) {
        Get.snackbar('Image too large',
            'Choose a photo under ${maxPickedImageBytes ~/ 1024}KB, or a smaller/more compressed one.');
        return;
      }
      final mimeType = picked.mimeType ?? mimeTypeForPath(picked.path);
      target.text = bytesToDataUrl(bytes, mimeType);
    } finally {
      isPicking.value = false;
    }
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
        shippingZones: shippingZones.toList(),
      );
      await _storeRepository.updateStore(updated);
      scope.current.value = updated;
      return true;
    } finally {
      isSaving.value = false;
    }
  }
}
