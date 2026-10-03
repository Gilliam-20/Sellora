import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/i18n/countries.dart';
import '../../../core/utils/image_data_url.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/common.dart';
import 'store_customize_controller.dart';

class StoreCustomizeView extends GetView<StoreCustomizeController> {
  const StoreCustomizeView({super.key});

  Future<void> _save(BuildContext context) async {
    final success = await controller.save();
    if (success) {
      Get.snackbar('Store updated', 'Your storefront settings were saved.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Store details')),
      body: ResponsiveCenter(
        maxWidth: 560,
        child: ListView(
          padding: EdgeInsets.symmetric(
              horizontal: context.pageHorizontalPadding,
              vertical: AppSpacing.lg),
          children: [
            TextField(
              controller: controller.nameCtrl,
              decoration: const InputDecoration(labelText: 'Store name'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller.taglineCtrl,
              decoration: const InputDecoration(
                  labelText: 'Tagline',
                  hintText: 'A short line under your name'),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Logo', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ImagePreview(
                    controller: controller.logoUrlCtrl, isCircle: true),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: controller.logoUrlCtrl,
                    decoration: const InputDecoration(labelText: 'Logo URL'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Obx(() => OutlinedButton.icon(
                  onPressed: controller.isPickingLogo.value
                      ? null
                      : controller.pickLogo,
                  icon: controller.isPickingLogo.value
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_outlined),
                  label: const Text('Upload from device'),
                )),
            const SizedBox(height: AppSpacing.lg),
            Material(
              color: AppColors.cargoNavy.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppRadii.stub),
              child: ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Colors, fonts, banner and homepage'),
                subtitle: const Text(
                    'Set your storefront theme and homepage sections in Store design.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Get.toNamed(Routes.sellerStoreDesign),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Shipping zones',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Customers can only check out to countries in the zones you '
              'ship to. Each zone is priced in its own currency.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Obx(
              () => Column(
                children: ShippingZone.values.map((zone) {
                  final enabled = controller.shippingZones.contains(zone.id);
                  final countryCount = zone.countries.length;
                  return CheckboxListTile(
                    value: enabled,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(zone.label),
                    subtitle: Text('${zone.currency} · $countryCount '
                        '${countryCount == 1 ? 'country' : 'countries'}'),
                    onChanged: (_) {
                      if (!controller.toggleZone(zone.id)) {
                        Get.snackbar('Keep at least one zone',
                            'Your store needs somewhere to ship to.');
                      }
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
      bottomNavigationBar: Obx(() => BottomActionBar(
            label: 'Save changes',
            isLoading: controller.isSaving.value,
            onPressed: controller.isSaving.value ? null : () => _save(context),
          )),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.controller, required this.isCircle});

  final TextEditingController controller;
  final bool isCircle;

  @override
  Widget build(BuildContext context) {
    final size = isCircle ? 56.0 : double.infinity;
    final height = isCircle ? 56.0 : 100.0;
    final placeholder = Container(
      width: size,
      height: height,
      color: AppColors.mist,
      child: const Icon(Icons.image_outlined, color: AppColors.slate),
    );
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final url = controller.text.trim();
        Widget child;
        if (url.isEmpty) {
          child = placeholder;
        } else if (isDataUrl(url)) {
          final bytes = decodeDataUrl(url);
          child = bytes == null
              ? placeholder
              : Image.memory(
                  bytes,
                  width: size,
                  height: height,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => placeholder,
                );
        } else {
          child = CachedNetworkImage(
            imageUrl: url,
            width: size,
            height: height,
            fit: BoxFit.cover,
            placeholder: (_, __) => placeholder,
            errorWidget: (_, __, ___) => placeholder,
          );
        }
        return ClipRRect(
          borderRadius: isCircle
              ? BorderRadius.circular(28)
              : BorderRadius.circular(AppRadii.card),
          child: SizedBox(width: size, height: height, child: child),
        );
      },
    );
  }
}
