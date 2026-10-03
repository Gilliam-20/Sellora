import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/listing_text.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_page.dart';
import '../../../core/widgets/common.dart';
import '../../../data/models/fee_settings.dart';
import '../../../data/models/product_model.dart';
import 'product_import_controller.dart';

/// The CJ → store import editor (TODO.md §13): real images/description from
/// `getProductDetail`, then everything the seller changes before it goes
/// live — title and description, which images to keep and which is the
/// main one, which variants to sell and their SKUs, tags, SEO text, and a
/// margin-based price — saved as a draft or published.
///
/// No collection picker: collections don't exist yet (PHASE 5).
class ProductImportView extends StatefulWidget {
  const ProductImportView({super.key});

  @override
  State<ProductImportView> createState() => _ProductImportViewState();
}

class _ProductImportViewState extends State<ProductImportView> {
  static const _marginPresets = [20, 30, 50, 100];

  final _formKey = GlobalKey<FormState>();
  final _priceCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _seoTitleCtrl = TextEditingController();
  final _seoDescriptionCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  bool _userEditedPrice = false;
  bool _settingPriceProgrammatically = false;
  bool _userEditedText = false;
  Worker? _productWorker;
  Worker? _variantWorker;
  Worker? _feeWorker;

  ProductImportController get controller => Get.find<ProductImportController>();

  @override
  void initState() {
    super.initState();
    _priceCtrl.addListener(() {
      if (!_settingPriceProgrammatically) _userEditedPrice = true;
      setState(() {});
    });
    for (final ctrl in [_titleCtrl, _descriptionCtrl]) {
      ctrl.addListener(() => _userEditedText = true);
    }
    _seoTitleCtrl.addListener(() => setState(() {}));
    _seoDescriptionCtrl.addListener(() => setState(() {}));
    _applyProductText();
    _applySuggestedPrice();
    // Re-suggest whenever the full detail arrives or the seller switches
    // variants — but only while they haven't typed/picked a price
    // themselves, so this never clobbers a deliberate choice.
    _productWorker = ever<ProductModel?>(controller.product, (_) {
      _applyProductText();
      _applySuggestedPrice();
    });
    _variantWorker = ever<ProductVariant?>(
        controller.selectedVariant, (_) => _applySuggestedPrice());
    _feeWorker = ever<FeeSettings>(controller.fees, (_) => setState(() {}));
  }

  /// Fills the title/description from CJ until the seller edits either.
  void _applyProductText() {
    if (_userEditedText) return;
    final product = controller.product.value;
    if (product == null) return;
    _titleCtrl.text = product.title;
    final description = ListingText.plain(product.description);
    _descriptionCtrl.text =
        description.length > 5000 ? description.substring(0, 5000) : description;
    _userEditedText = false;
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
    _userEditedPrice =
        true; // an explicit choice — a later variant switch shouldn't override it
    setState(() {});
  }

  void _suggestSeo() {
    _seoTitleCtrl.text = ListingText.suggestSeoTitle(_titleCtrl.text);
    _seoDescriptionCtrl.text = ListingText.suggestSeoDescription(
        _descriptionCtrl.text, _titleCtrl.text);
  }

  void _addTags() {
    controller.addTags(_tagCtrl.text);
    _tagCtrl.clear();
  }

  Future<void> _submit({required bool publish}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_tagCtrl.text.trim().isNotEmpty) _addTags();
    final draft = ImportDraft(
      title: _titleCtrl.text,
      description: _descriptionCtrl.text,
      sellPrice: double.parse(_priceCtrl.text.trim()),
      seoTitle: _seoTitleCtrl.text,
      seoDescription: _seoDescriptionCtrl.text,
    );
    final success = await controller.import(draft, publish: publish);
    Get.back();
    if (success) {
      final title = draft.title.trim();
      Get.snackbar(
        publish ? 'Imported' : 'Saved as draft',
        publish
            ? '$title is now live in your store.'
            : '$title was saved to My listings as a draft.',
      );
    }
  }

  @override
  void dispose() {
    _productWorker?.dispose();
    _variantWorker?.dispose();
    _feeWorker?.dispose();
    for (final ctrl in [
      _priceCtrl,
      _titleCtrl,
      _descriptionCtrl,
      _seoTitleCtrl,
      _seoDescriptionCtrl,
      _tagCtrl,
    ]) {
      ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Import product')),
      body: Obx(() {
        final product = controller.product.value;
        if (product == null) return const AppLoadingState();

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
                  _ImageEditor(controller: controller),
                  const SizedBox(height: AppSpacing.xs),
                  Text('CJ ID: ${product.cjProductId} · ${product.category}',
                      style: textTheme.bodySmall),
                  const SizedBox(height: AppSpacing.lg),
                  _Section(
                    title: 'Details',
                    children: [
                      TextFormField(
                        controller: _titleCtrl,
                        maxLength: 200,
                        decoration: const InputDecoration(labelText: 'Title'),
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'Give the product a title'
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        controller: _descriptionCtrl,
                        minLines: 4,
                        maxLines: 10,
                        maxLength: 5000,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          alignLabelWithHint: true,
                          helperText:
                              'Shown on your storefront. CJ\'s formatting was removed.',
                        ),
                      ),
                    ],
                  ),
                  if (product.variants.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _Section(
                      title: 'Variants',
                      subtitle: product.variants.length > 1
                          ? 'Tap a variant to price from it. Switch off any '
                              'you don\'t want to sell.'
                          : null,
                      children: [
                        _VariantEditor(controller: controller),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  _PricingCard(
                    costPrice: controller.costPrice,
                    shippingCost: controller.shippingCost,
                    earningFor: controller.sellerEarning,
                    fees: controller.fees.value,
                    isLoadingShipping: controller.isLoadingShipping.value,
                    shippingError: controller.shippingError.value,
                    currency: controller.currencyCode,
                    priceFloor: controller.priceFloor,
                    priceCtrl: _priceCtrl,
                    marginPresets: _marginPresets,
                    onPresetSelected: _applyMarginPreset,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _Section(
                    title: 'Tags',
                    subtitle:
                        'Up to ${ProductModel.maxTags}, to group and find '
                        'your products. Separate with commas.',
                    children: [
                      TextField(
                        controller: _tagCtrl,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _addTags(),
                        decoration: InputDecoration(
                          labelText: 'Add tags',
                          hintText: 'e.g. summer, gifts',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.add),
                            tooltip: 'Add',
                            onPressed: _addTags,
                          ),
                        ),
                      ),
                      if (controller.tags.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: controller.tags
                              .map((tag) => InputChip(
                                    label: Text(tag),
                                    onDeleted: () => controller.removeTag(tag),
                                  ))
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _Section(
                    title: 'Search engine listing',
                    subtitle:
                        'How this product appears in search results and link '
                        'previews. Left blank, the title and description are used.',
                    trailing: TextButton.icon(
                      onPressed: _suggestSeo,
                      icon: const Icon(Icons.auto_fix_high, size: 18),
                      label: const Text('Suggest'),
                    ),
                    children: [
                      _SeoPreview(
                        title: _seoTitleCtrl.text.trim().isNotEmpty
                            ? _seoTitleCtrl.text.trim()
                            : _titleCtrl.text.trim(),
                        description: _seoDescriptionCtrl.text.trim().isNotEmpty
                            ? _seoDescriptionCtrl.text.trim()
                            : ListingText.clip(
                                _descriptionCtrl.text,
                                ListingText.seoDescriptionTarget),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        controller: _seoTitleCtrl,
                        maxLength: ListingText.seoTitleMax,
                        decoration: InputDecoration(
                          labelText: 'Page title',
                          helperText: _lengthHint(_seoTitleCtrl.text,
                              ListingText.seoTitleTarget),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        controller: _seoDescriptionCtrl,
                        minLines: 2,
                        maxLines: 4,
                        maxLength: ListingText.seoDescriptionMax,
                        decoration: InputDecoration(
                          labelText: 'Meta description',
                          alignLabelWithHint: true,
                          helperText: _lengthHint(_seoDescriptionCtrl.text,
                              ListingText.seoDescriptionTarget),
                        ),
                      ),
                    ],
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
                            onPressed: submitting
                                ? null
                                : () => _submit(publish: false),
                            child: const Text('Save as draft'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: submitting
                                ? null
                                : () => _submit(publish: true),
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

  /// "42 of ~60 characters", or a nudge once past what search shows.
  static String _lengthHint(String text, int target) {
    final length = text.trim().length;
    return length > target
        ? '$length characters; search results usually show about $target'
        : '$length of about $target characters';
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
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
          Row(
            children: [
              Expanded(child: Text(title, style: textTheme.titleSmall)),
              if (trailing != null) trailing!,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(subtitle!, style: textTheme.bodySmall),
          ],
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
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
              child:
                  Text(message, style: Theme.of(context).textTheme.bodySmall)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// The big preview, then every image CJ offers: tap to preview, the check
/// to keep or drop it, and "Make main image" for the previewed one.
class _ImageEditor extends StatelessWidget {
  const _ImageEditor({required this.controller});
  final ProductImportController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final urls = controller.availableImages;
      final kept = controller.selectedImages;
      final preview = controller.previewImage.value.isNotEmpty
          ? controller.previewImage.value
          : (kept.isNotEmpty ? kept.first : '');
      final isMain = kept.isNotEmpty && kept.first == preview;
      final isKept = kept.contains(preview);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                    if (preview.isNotEmpty)
                      Opacity(
                        opacity: isKept ? 1 : 0.4,
                        child: CachedNetworkImage(
                            imageUrl: preview,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                Container(color: AppColors.mist),
                            errorWidget: (_, __, ___) =>
                                Container(color: AppColors.mist)),
                      ),
                    if (isMain)
                      const Positioned(
                        left: 10,
                        top: 10,
                        child: _Badge(label: 'Main image'),
                      ),
                    if (controller.isLoading.value)
                      const Positioned(
                          right: 10, top: 10, child: SelloraLoader(size: 20)),
                  ],
                ),
              ),
            ),
          ),
          if (urls.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${kept.length} of ${urls.length} images kept',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (isKept && !isMain)
                  TextButton(
                    onPressed: () => controller.makeMainImage(preview),
                    child: const Text('Make main image'),
                  ),
              ],
            ),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: urls.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final url = urls[index];
                  final selected = kept.contains(url);
                  return _Thumbnail(
                    url: url,
                    kept: selected,
                    previewed: url == preview,
                    onTap: () => controller.showImage(url),
                    onToggle: () => controller.toggleImage(url),
                  );
                },
              ),
            ),
          ],
        ],
      );
    });
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(AppRadii.stub),
      ),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: AppColors.cloud)),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.url,
    required this.kept,
    required this.previewed,
    required this.onTap,
    required this.onToggle,
  });

  final String url;
  final bool kept;
  final bool previewed;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: kept ? 'Kept image' : 'Dropped image',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 64,
          height: 64,
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.stub),
                    border: Border.all(
                      color: previewed
                          ? AppColors.manifestGold
                          : AppColors.hairline,
                      width: previewed ? 2 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.stub - 1),
                    child: Opacity(
                      opacity: kept ? 1 : 0.35,
                      child: CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              Container(color: AppColors.mist),
                          errorWidget: (_, __, ___) =>
                              Container(color: AppColors.mist)),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: InkWell(
                  onTap: onToggle,
                  customBorder: const CircleBorder(),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      kept ? Icons.check_circle : Icons.add_circle_outline,
                      size: 20,
                      color:
                          kept ? AppColors.horizonTealDeep : AppColors.slate,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row per CJ variant: on/off for buyers, its CJ cost, and an editable
/// SKU. Tapping the label prices the listing from that variant.
class _VariantEditor extends StatelessWidget {
  const _VariantEditor({required this.controller});
  final ProductImportController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final product = controller.product.value;
      if (product == null) return const SizedBox.shrink();
      final selected = controller.selectedVariant.value;
      // Read so this Obx rebuilds on a toggle.
      controller.enabledVids.length;
      return Column(
        children: product.variants.map((variant) {
          final enabled = controller.isVariantEnabled(variant);
          final isSelected = selected?.vid == variant.vid;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Switch(
                  value: enabled,
                  onChanged: (_) => controller.toggleVariant(variant),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  flex: 3,
                  child: InkWell(
                    onTap: () => controller.selectVariant(variant),
                    borderRadius: BorderRadius.circular(AppRadii.stub),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            variant.label.isEmpty ? 'Default' : variant.label,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: enabled ? null : AppColors.slate,
                                ),
                          ),
                          Text(
                            'CJ cost ${Formatters.currency(variant.costPrice, code: controller.currencyCode)}'
                            '${isSelected ? ' · pricing from this' : ''}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    key: ValueKey('sku-${variant.vid}'),
                    initialValue: controller.skuFor(variant),
                    enabled: enabled,
                    maxLength: 64,
                    decoration: const InputDecoration(
                      labelText: 'SKU',
                      isDense: true,
                      counterText: '',
                    ),
                    onChanged: (value) => controller.setSku(variant, value),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      );
    });
  }
}

/// A search-result-shaped preview of the SEO fields.
class _SeoPreview extends StatelessWidget {
  const _SeoPreview({required this.title, required this.description});
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.mist,
        borderRadius: BorderRadius.circular(AppRadii.stub),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ListingText.clip(title.isEmpty ? 'Product title' : title,
                ListingText.seoTitleTarget),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleSmall?.copyWith(color: AppColors.cargoNavy),
          ),
          const SizedBox(height: 2),
          Text(
            description.isEmpty ? 'No description yet.' : description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PricingCard extends StatelessWidget {
  const _PricingCard({
    required this.costPrice,
    required this.shippingCost,
    required this.earningFor,
    required this.fees,
    required this.isLoadingShipping,
    required this.shippingError,
    required this.currency,
    required this.priceFloor,
    required this.priceCtrl,
    required this.marginPresets,
    required this.onPresetSelected,
  });

  final double costPrice;
  final double shippingCost;
  /// See [ProductImportController.sellerEarning].
  final double Function(double price) earningFor;
  final FeeSettings fees;
  final bool isLoadingShipping;
  final String? shippingError;
  final String currency;

  /// See [ProductImportController.priceFloor].
  final double priceFloor;
  final TextEditingController priceCtrl;
  final List<int> marginPresets;
  final ValueChanged<int> onPresetSelected;

  @override
  Widget build(BuildContext context) {
    final price = double.tryParse(priceCtrl.text.trim()) ?? 0;
    final profit = earningFor(price);
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
              Text('CJ cost price',
                  style: Theme.of(context).textTheme.bodyMedium),
              Text(Formatters.currency(costPrice, code: currency),
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Shipping to Kenya (buyer pays)',
                  style: Theme.of(context).textTheme.bodyMedium),
              if (isLoadingShipping)
                const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else if (shippingError != null)
                Text('—', style: Theme.of(context).textTheme.bodyMedium)
              else
                Text(Formatters.currency(shippingCost, code: currency),
                    style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const Divider(height: AppSpacing.md),
          Text(
            fees.chargeOnShipping
                ? 'You keep your price less Sellora\'s ${fees.percentLabel}% '
                    'fee (charged on the product and its shipping), less '
                    'CJ\'s cost. Shipping is charged to the buyer on top.'
                : 'You keep your price less Sellora\'s ${fees.percentLabel}% '
                    'fee, less CJ\'s cost. Shipping is charged to the buyer '
                    'on top.',
            style: Theme.of(context).textTheme.bodySmall,
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
            validator: (value) {
              final error = Validators.price(value);
              if (error != null) return error;
              final price = double.parse(value!.trim());
              if (price < priceFloor) {
                return 'At least ${Formatters.currency(priceFloor, code: currency)} '
                    'to cover the supplier cost and service fee';
              }
              return null;
            },
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
              Expanded(
                child: Text(
                  'You earn ${Formatters.currency(profit, code: currency)} · ${marginPercent.toStringAsFixed(0)}% on cost',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isHealthy
                          ? AppColors.horizonTealDeep
                          : AppColors.danger,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
