import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_page.dart';
import '../../../core/widgets/common.dart';
import '../../../data/models/product_model.dart';
import 'product_import_controller.dart';

/// CJ product detail + import screen. Replaces the old catalog bottom sheet
/// (a single flat price field) with the full "Product Import Workflow":
/// real images/description from `getProductDetail`, a variant picker when
/// the product has more than one purchasable SKU, and a margin-based
/// smart-pricing calculator. Deliberately does not add title/description
/// editing, tags, collections or SEO fields — those need concepts
/// (collections, SEO slugs) that don't exist anywhere in the app yet, and
/// were scoped out of this pass.
class ProductImportView extends StatefulWidget {
  const ProductImportView({super.key});

  @override
  State<ProductImportView> createState() => _ProductImportViewState();
}

class _ProductImportViewState extends State<ProductImportView> {
  static const _marginPresets = [20, 30, 50, 100];

  final _formKey = GlobalKey<FormState>();
  final _priceCtrl = TextEditingController();
  bool _userEditedPrice = false;
  bool _settingPriceProgrammatically = false;
  Worker? _productWorker;
  Worker? _variantWorker;

  ProductImportController get controller =>
      Get.find<ProductImportController>();

  @override
  void initState() {
    super.initState();
    _priceCtrl.addListener(() {
      if (!_settingPriceProgrammatically) _userEditedPrice = true;
      setState(() {});
    });
    _applySuggestedPrice();
    // Re-suggest whenever the full detail arrives or the seller switches
    // variants — but only while they haven't typed/picked a price
    // themselves, so this never clobbers a deliberate choice.
    _productWorker =
        ever<ProductModel?>(controller.product, (_) => _applySuggestedPrice());
    _variantWorker = ever<ProductVariant?>(
        controller.selectedVariant, (_) => _applySuggestedPrice());
  }

  void _applySuggestedPrice() {
    if (_userEditedPrice) return;
    final suggested = controller.suggestedRetailPrice;
    if (suggested <= 0) return;
    _settingPriceProgrammatically = true;
    _priceCtrl.text = suggested.toStringAsFixed(2);
    _settingPriceProgrammatically = false;
  }

  void _applyMarginPreset(int percent) {
    final price = controller.priceForMargin(percent.toDouble());
    _settingPriceProgrammatically = true;
    _priceCtrl.text = price.toStringAsFixed(2);
    _settingPriceProgrammatically = false;
    _userEditedPrice = true; // an explicit choice — a later variant switch shouldn't override it
    setState(() {});
  }

  Future<void> _submit({required bool publish}) async {
    if (!_formKey.currentState!.validate()) return;
    final price = double.parse(_priceCtrl.text.trim());
    final success = await controller.import(sellPrice: price, publish: publish);
    Get.back();
    if (success) {
      Get.snackbar(
        publish ? 'Imported' : 'Saved as draft',
        publish
            ? '${controller.product.value?.title ?? 'Product'} is now live in your store.'
            : '${controller.product.value?.title ?? 'Product'} was saved to My listings as a draft.',
      );
    }
  }

  @override
  void dispose() {
    _productWorker?.dispose();
    _variantWorker?.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import product')),
      body: Obx(() {
        final product = controller.product.value;
        if (product == null) return const AppLoadingState();

        final gallery = <String>{
          controller.previewImage.value,
          product.imageUrl,
          ...product.images,
        }.where((url) => url.isNotEmpty).toList();

        return SingleChildScrollView(
          child: ResponsiveCenter(
            maxWidth: 720,
            padding: EdgeInsets.symmetric(
                horizontal: context.pageHorizontalPadding,
                vertical: AppSpacing.md),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (controller.errorMessage.value != null)
                    _InlineWarning(
                      message: controller.errorMessage.value!,
                      onRetry: controller.loadDetail,
                    ),
                  _Gallery(
                    urls: gallery,
                    selected: controller.previewImage.value,
                    onSelect: controller.showImage,
                    isLoading: controller.isLoading.value,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(product.title,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.xs),
                  Text('CJ ID: ${product.cjProductId} · ${product.category}',
                      style: Theme.of(context).textTheme.bodySmall),
                  if (product.description.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text('Description',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: AppSpacing.xs),
                    Text(product.description,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                  if (product.variants.length > 1) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text('Choose a variant to price from',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: AppSpacing.sm),
                    _VariantPicker(
                      variants: product.variants,
                      selected: controller.selectedVariant.value,
                      currency: controller.currencyCode,
                      onSelect: controller.selectVariant,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  _PricingCard(
                    costPrice: controller.costPrice,
                    currency: controller.currencyCode,
                    priceCtrl: _priceCtrl,
                    marginPresets: _marginPresets,
                    onPresetSelected: _applyMarginPreset,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                ],
              ),
            ),
          ),
        );
      }),
      bottomNavigationBar: Obx(() {
        final submitting = controller.isSubmitting.value;
        return Container(
          padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm,
              AppSpacing.md, AppSpacing.md + MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(
            color: AppColors.cloud,
            border: Border(top: BorderSide(color: AppColors.hairline)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed:
                                submitting ? null : () => _submit(publish: false),
                            child: const Text('Save as draft'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: ElevatedButton(
                            onPressed:
                                submitting ? null : () => _submit(publish: true),
                            child: submitting
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: AppColors.ink))
                                : const Text('Publish to store'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _InlineWarning extends StatelessWidget {
  const _InlineWarning({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.stub),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 18, color: AppColors.manifestGoldDeep),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
              child: Text(message, style: Theme.of(context).textTheme.bodySmall)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery({
    required this.urls,
    required this.selected,
    required this.onSelect,
    required this.isLoading,
  });

  final List<String> urls;
  final String selected;
  final ValueChanged<String> onSelect;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final main = selected.isNotEmpty ? selected : (urls.isNotEmpty ? urls.first : '');
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: AspectRatio(
            aspectRatio: 1.3,
            child: Container(
              color: AppColors.mist,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (main.isNotEmpty)
                    CachedNetworkImage(imageUrl: main, fit: BoxFit.cover),
                  if (isLoading)
                    const Positioned(
                        right: 10, top: 10, child: SelloraLoader(size: 20)),
                ],
              ),
            ),
          ),
        ),
        if (urls.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 56,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: urls
                    .map((url) => Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.sm),
                          child: GestureDetector(
                            onTap: () => onSelect(url),
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(AppRadii.stub),
                                border: Border.all(
                                  color: url == main
                                      ? AppColors.manifestGold
                                      : AppColors.hairline,
                                  width: url == main ? 2 : 1,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(AppRadii.stub - 1),
                                child: CachedNetworkImage(
                                    imageUrl: url, fit: BoxFit.cover),
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _VariantPicker extends StatelessWidget {
  const _VariantPicker({
    required this.variants,
    required this.selected,
    required this.currency,
    required this.onSelect,
  });

  final List<ProductVariant> variants;
  final ProductVariant? selected;
  final String currency;
  final ValueChanged<ProductVariant> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: variants.map((variant) {
        final isSelected = selected?.vid == variant.vid;
        return ChoiceChip(
          label: Text(
              '${variant.label} · ${Formatters.currency(variant.costPrice, code: currency)}'),
          selected: isSelected,
          selectedColor: AppColors.manifestGold.withValues(alpha: 0.3),
          onSelected: (_) => onSelect(variant),
        );
      }).toList(),
    );
  }
}

class _PricingCard extends StatelessWidget {
  const _PricingCard({
    required this.costPrice,
    required this.currency,
    required this.priceCtrl,
    required this.marginPresets,
    required this.onPresetSelected,
  });

  final double costPrice;
  final String currency;
  final TextEditingController priceCtrl;
  final List<int> marginPresets;
  final ValueChanged<int> onPresetSelected;

  @override
  Widget build(BuildContext context) {
    final price = double.tryParse(priceCtrl.text.trim()) ?? 0;
    final profit = price - costPrice;
    final marginPercent = costPrice == 0 ? 0.0 : (profit / costPrice) * 100;
    final isHealthy = profit > 0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cloud,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Smart pricing', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('CJ cost price', style: Theme.of(context).textTheme.bodyMedium),
              Text(Formatters.currency(costPrice, code: currency),
                  style: AppTypography.price(size: 16)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Quick margin', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            children: marginPresets
                .map((m) => ActionChip(
                      label: Text('+$m%'),
                      onPressed: () => onPresetSelected(m),
                    ))
                .toList(),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Your sell price'),
            validator: Validators.price,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                isHealthy ? Icons.trending_up : Icons.trending_down,
                size: 16,
                color: isHealthy ? AppColors.horizonTealDeep : AppColors.danger,
              ),
              const SizedBox(width: 4),
              Text(
                'Profit ${Formatters.currency(profit, code: currency)} · Margin ${marginPercent.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isHealthy ? AppColors.horizonTealDeep : AppColors.danger,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
