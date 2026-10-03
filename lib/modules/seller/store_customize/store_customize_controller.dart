import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/image_data_url.dart';
import '../../../data/models/store_model.dart';
import '../../../data/repositories/store_repository.dart';
import '../../storefront/store_scope.dart';

/// Store details: name, tagline, logo and shipping zones. Colors, the
/// banner and everything else on the storefront are the store builder's
/// (`lib/modules/seller/store_builder/`).
class StoreCustomizeController extends GetxController {
  StoreCustomizeController({StoreScope? scope, StoreRepository? repository})
      : scope = scope ?? Get.find<StoreScope>(),
        _storeRepository = repository ?? Get.find<StoreRepository>();

  final StoreScope scope;
  final StoreRepository _storeRepository;

  late final TextEditingController nameCtrl;
  late final TextEditingController taglineCtrl;
  late final TextEditingController logoUrlCtrl;

  /// Enabled `ShippingZone` ids — checkout only offers countries in these.
  final shippingZones = <String>[].obs;
  final isSaving = false.obs;
  final isPickingLogo = false.obs;

  final _picker = ImagePicker();

  @override
  void onInit() {
    super.onInit();
    final store = scope.current.value;
    nameCtrl = TextEditingController(text: store?.name);
    taglineCtrl = TextEditingController(text: store?.tagline);
    logoUrlCtrl = TextEditingController(text: store?.logoUrl);
    shippingZones
        .assignAll(store?.shippingZones ?? StoreModel.allShippingZoneIds);
  }

  @override
  void onClose() {
    nameCtrl.dispose();
    taglineCtrl.dispose();
    logoUrlCtrl.dispose();
    super.onClose();
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

  Future<void> pickLogo() => _pickImage(logoUrlCtrl, isPickingLogo, 'logo');

  /// Uploads the picked photo to Supabase Storage and puts its public URL
  /// in [target]; Save then writes that URL onto the store like a pasted one.
  Future<void> _pickImage(
      TextEditingController target, RxBool isPicking, String kind) async {
    final store = scope.current.value;
    if (store == null) return;
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
            'Choose a photo under ${maxPickedImageBytes ~/ (1024 * 1024)}MB.');
        return;
      }
      final mimeType = picked.mimeType ?? mimeTypeForPath(picked.path);
      target.text = await _storeRepository.uploadStoreImage(
        store.id,
        bytes,
        contentType: mimeType,
        kind: kind,
      );
    } catch (e) {
      debugPrint('StoreCustomizeController: upload failed: $e');
      Get.snackbar('Upload failed',
          'The photo could not be uploaded. Check your connection and try again.');
    } finally {
      isPicking.value = false;
    }
  }

  Future<bool> save() async {
    final store = scope.current.value;
    if (store == null) return false;
    isSaving.value = true;
    try {
      final updated = store.copyWith(
        name: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
        tagline: taglineCtrl.text.trim(),
        logoUrl: logoUrlCtrl.text.trim(),
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
