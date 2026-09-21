import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../data/models/product_model.dart';
import 'manage_variants_controller.dart';

class ManageVariantsView extends GetView<ManageVariantsController> {
  const ManageVariantsView({super.key});

  Future<void> _save(BuildContext context) async {
    final success = await controller.save();
    if (success) {
      Get.back();
      Get.snackbar('Variants updated',
          '${controller.product.title}\'s variants were saved.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage variants')),
      body: Obx(() {
        if (controller.variants.isEmpty) {
          return const EmptyState(
            icon: Icons.style_outlined,
            title: 'No variants',
            message: 'This product was imported with a single SKU, so '
                'there is nothing to manage here.',
          );
        }
        return ResponsiveCenter(
          maxWidth: 720,
          child: ListView.separated(
            padding: EdgeInsets.symmetric(
                horizontal: context.pageHorizontalPadding,
                vertical: AppSpacing.md),
            itemCount: controller.variants.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              return _VariantEditorCard(
                variant: controller.variants[index],
                currency: controller.product.currency,
                onEnabledChanged: (enabled) =>
                    controller.setEnabled(index, enabled),
                onSkuChanged: (sku) => controller.setSku(index, sku),
              );
            },
          ),
        );
      }),
      bottomNavigationBar: Obx(() {
        if (controller.variants.isEmpty) return const SizedBox.shrink();
        final saving = controller.isSaving.value;
        return Container(
          padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.md + MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(
            color: AppColors.cloud,
            border: Border(top: BorderSide(color: AppColors.hairline)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: saving ? null : () => _save(context),
                child: saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.ink))
                    : const Text('Save changes'),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _VariantEditorCard extends StatefulWidget {
  const _VariantEditorCard({
    required this.variant,
    required this.currency,
    required this.onEnabledChanged,
    required this.onSkuChanged,
  });

  final ProductVariant variant;
  final String currency;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<String> onSkuChanged;

  @override
  State<_VariantEditorCard> createState() => _VariantEditorCardState();
}

class _VariantEditorCardState extends State<_VariantEditorCard> {
  late final TextEditingController _skuCtrl =
      TextEditingController(text: widget.variant.sku);

  @override
  void dispose() {
    _skuCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final variant = widget.variant;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: variant.enabled ? AppColors.cloud : AppColors.mist,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.stub),
                child: variant.image != null && variant.image!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: variant.image!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                            width: 48, height: 48, color: AppColors.mist),
                        errorWidget: (_, __, ___) => Container(
                            width: 48, height: 48, color: AppColors.mist))
                    : Container(width: 48, height: 48, color: AppColors.mist),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(variant.label,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 2),
                    Text(
                      'CJ cost ${Formatters.currency(variant.costPrice, code: widget.currency)}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              Switch(
                value: variant.enabled,
                activeColor: AppColors.horizonTeal,
                onChanged: widget.onEnabledChanged,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _skuCtrl,
            decoration: const InputDecoration(
                labelText: 'Your SKU (optional, for your own reference)'),
            onChanged: widget.onSkuChanged,
          ),
        ],
      ),
    );
  }
}
