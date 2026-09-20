import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/color_utils.dart';
import '../../../core/utils/image_data_url.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/common.dart';
import 'store_customize_controller.dart';

const _presetHexes = [
  '#303F9F', // Cargo Navy
  '#FFC107', // Manifest Gold
  '#2EC4B6', // Horizon Teal
  '#E0553F', // Danger red, as a bold option
  '#8C6FE0', // Admin purple, as a bold option
];

class StoreCustomizeView extends GetView<StoreCustomizeController> {
  const StoreCustomizeView({super.key});

  Future<void> _save(BuildContext context) async {
    final success = await controller.save();
    if (success) {
      Get.snackbar('Store updated', 'Your storefront branding was saved.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customize store')),
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
            Text('Banner', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: controller.bannerUrlCtrl,
              decoration: const InputDecoration(labelText: 'Banner URL'),
            ),
            const SizedBox(height: AppSpacing.sm),
            _ImagePreview(
                controller: controller.bannerUrlCtrl, isCircle: false),
            const SizedBox(height: AppSpacing.sm),
            Obx(() => OutlinedButton.icon(
                  onPressed: controller.isPickingBanner.value
                      ? null
                      : controller.pickBanner,
                  icon: controller.isPickingBanner.value
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_outlined),
                  label: const Text('Upload from device'),
                )),
            const SizedBox(height: AppSpacing.lg),
            Text('Accent color', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Obx(
              () => Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: _presetHexes.map((hex) {
                  final selected = controller.colorHex.value?.toUpperCase() ==
                      hex.toUpperCase();
                  return GestureDetector(
                    onTap: () => controller.selectPreset(hex),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: hexToColor(hex),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? AppColors.ink : AppColors.hairline,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: selected
                          ? const Icon(Icons.check,
                              color: AppColors.cloud, size: 18)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: controller.hexCtrl,
              decoration: const InputDecoration(
                  labelText: 'Hex color', hintText: '#16213E'),
              onChanged: controller.setHexFromField,
            ),
            Obx(() {
              final error = Validators.hexColor(controller.colorHex.value);
              if (error == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(error,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: AppColors.danger)),
              );
            }),
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
